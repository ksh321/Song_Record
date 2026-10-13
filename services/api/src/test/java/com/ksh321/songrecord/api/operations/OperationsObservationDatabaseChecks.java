package com.ksh321.songrecord.api.operations;
import java.time.*;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
public final class OperationsObservationDatabaseChecks {
 public static void verify(JdbcTemplate db){
  var now=Instant.parse("2026-10-13T00:00:00Z");var writer=new OperationsRecorder(db,new DataSourceTransactionManager(db.getDataSource()));var owner=UUID.randomUUID();var target=UUID.randomUUID();
  for(int i=0;i<3;i++){
   writer.record(owner,target,"USER",OperationsContext.Action.RECORDING_SAVED,OperationsContext.Result.SUCCESS,200,1,now);
   writer.record(owner,target,"USER",OperationsContext.Action.PIN,OperationsContext.Result.PIN_LIMIT_REACHED,409,2,now);
   writer.record(owner,target,"USER",OperationsContext.Action.OTHER,OperationsContext.Result.QUOTA_EXCEEDED,409,2,now);
  }
  writer.record(owner,UUID.randomUUID(),"USER",OperationsContext.Action.RECORDING_SAVED,OperationsContext.Result.SUCCESS,200,2,now);
  writer.record(UUID.randomUUID(),target,"USER",OperationsContext.Action.SONG_READ,OperationsContext.Result.SUCCESS,200,2,now.minus(Duration.ofDays(31)));
  writer.record(UUID.randomUUID(),target,"USER",OperationsContext.Action.RECORDING_SAVED,OperationsContext.Result.FAILURE,500,2,now);
  db.update("INSERT INTO operations_observation(id,actor_id,actor_kind,action,result,status_code,duration_ms,observed_at) VALUES(?,?,'USER','PIN_SLOTS_TEN','SUCCESS',0,0,?)",bytes(UUID.randomUUID()),bytes(owner),java.sql.Timestamp.from(now));
  var row=OperationsMetrics.demand(db,now);
  assertThat(row.get("server_observed_active_accounts")).isEqualTo(1L);assertThat(row.get("pin_limit_accounts")).isEqualTo(1L);assertThat(row.get("quota_accounts")).isEqualTo(1L);assertThat(row.get("second_recording_save_accounts")).isEqualTo(1L);assertThat(row.get("actual_playback_accounts")).isNull();
  assertThat(row.get("server_observed_active_pin_ten_accounts")).isEqualTo(1L);
  var tx=new org.springframework.transaction.support.TransactionTemplate(new DataSourceTransactionManager(db.getDataSource()));long before=db.queryForObject("SELECT COUNT(*) FROM operations_observation",Long.class);
  assertThatThrownBy(()->tx.execute(s->{writer.afterCommit(owner,target,OperationsContext.Action.JOB_SUCCESS,now);throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation",Long.class)).isEqualTo(before);
  tx.executeWithoutResult(s->writer.afterCommit(owner,target,OperationsContext.Action.JOB_SUCCESS,now));
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation",Long.class)).isEqualTo(before+1);
 }
 public static void verifyTriggers(JdbcTemplate db){
  var owner=com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.account(db);var device=com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.device(db,owner);
  db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(owner));
  var first=com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");
  var next=com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");
  for(var recording:java.util.List.of(first,next)){var generation=UUID.randomUUID();db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,cloud_revision,verified_size,sha256,generation,object_key,stored_at) VALUES(?,?,'STORED',1,6291456,?,?,?,CURRENT_TIMESTAMP)",bytes(recording),bytes(owner),"a".repeat(64),bytes(generation),new com.ksh321.songrecord.api.storage.StorageObjectKeys.Final(owner,recording,generation).value());}
  db.update("INSERT INTO pin_slot(user_id,slot_no,current_recording_id,operation_id,requested_at) VALUES(?,1,?,?,UTC_TIMESTAMP(3))",bytes(owner),bytes(first),bytes(UUID.randomUUID()));
  var tx=new org.springframework.transaction.support.TransactionTemplate(new DataSourceTransactionManager(db.getDataSource()));
  assertThatThrownBy(()->tx.execute(s->{db.update("UPDATE pin_slot SET current_recording_id=?,revision=revision+1 WHERE user_id=? AND slot_no=1",bytes(next),bytes(owner));throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE action='PIN_REPLACE_COMMITTED' AND actor_id=?",Long.class,bytes(owner))).isZero();
  db.update("UPDATE pin_slot SET current_recording_id=?,revision=revision+1 WHERE user_id=? AND slot_no=1",bytes(next),bytes(owner));
  var audit=db.queryForMap("SELECT actor_id,target_id,previous_target_id,result FROM operations_observation WHERE action='PIN_REPLACE_COMMITTED' AND actor_id=?",bytes(owner));
  assertThat((byte[])audit.get("target_id")).isEqualTo(bytes(next));assertThat((byte[])audit.get("previous_target_id")).isEqualTo(bytes(first));assertThat(audit.get("result")).isEqualTo("SUCCESS");
  for(int slot=2;slot<=10;slot++){var recording=com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id,operation_id,requested_at) VALUES(?,?,?,?,UTC_TIMESTAMP(3))",bytes(owner),slot,bytes(recording),bytes(UUID.randomUUID()));}
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE action='PIN_SLOTS_TEN' AND actor_id=?",Long.class,bytes(owner))).isGreaterThan(0);
  db.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision) VALUES(?,?,'RECORDING',?,1)",bytes(UUID.randomUUID()),bytes(owner),bytes(UUID.randomUUID()));
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE action='DELETE_COMMITTED' AND actor_id=?",Long.class,bytes(owner))).isEqualTo(1);
  var manager=new DataSourceTransactionManager(db.getDataSource());var writer=new OperationsRecorder(db,manager);
  var queue=new com.ksh321.songrecord.api.jobs.JobQueue(db,org.mockito.Mockito.mock(com.ksh321.songrecord.api.auth.AccountAccess.class),manager,Clock.systemUTC(),Duration.ofSeconds(10),3,writer::job);
  var job=new org.springframework.transaction.support.TransactionTemplate(manager).execute(s->queue.enqueueMaintenance(com.ksh321.songrecord.api.jobs.JobQueue.Type.ASSET_DELETE,UUID.randomUUID(),UUID.randomUUID(),"{}"));
  var lease=queue.claim(com.ksh321.songrecord.api.jobs.JobQueue.Type.ASSET_DELETE).orElseThrow();
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE action='JOB_CLAIM' AND job_id=?",Long.class,bytes(job))).isEqualTo(1);
  assertThatThrownBy(()->queue.complete(lease,()->{throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE action='JOB_SUCCESS' AND job_id=?",Long.class,bytes(job))).isZero();
  assertThat(queue.renew(lease)).isTrue();assertThat(queue.fail(lease,true)).isTrue();
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE action='JOB_RETRY' AND job_id=? AND result='FAILURE'",Long.class,bytes(job))).isEqualTo(1);
 }
}
