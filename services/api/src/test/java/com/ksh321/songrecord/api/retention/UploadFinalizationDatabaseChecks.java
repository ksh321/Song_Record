package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.auth.*;import com.ksh321.songrecord.api.uploads.*;import com.ksh321.songrecord.api.jobs.*;
import java.time.*;import java.util.*;import java.nio.*;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;import static org.mockito.Mockito.*;
public final class UploadFinalizationDatabaseChecks {
 public static void verify(JdbcTemplate db)throws Exception{
  var f=fixture(db);byte[] input={1,2,3};var audio=mock(AudioValidator.Validated.class);when(audio.bytes()).thenAnswer(c->ByteBuffer.wrap(input).asReadOnlyBuffer());when(audio.sha256()).thenReturn("a".repeat(64));
  var copied=new java.util.concurrent.atomic.AtomicReference<byte[]>();UploadFinalObjects writer=(key,buffer,hash)->{var data=new byte[buffer.remaining()];buffer.get(data);copied.set(data);};
  var finalizer=new UploadFinalization(db,writer,f.clock);
  Runnable effects=finalizer.prepare(f.lease,audio);assertThat(copied.get()).containsExactly(input);
  assertThat(db.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner))).isZero();
  assertThat(f.jobs.complete(f.lease,effects)).isTrue();assertThat(f.jobs.complete(f.lease,effects)).isFalse();
  assertThat(db.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner))).isEqualTo(3);
  assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner))).isZero();
  assertThat(db.queryForObject("SELECT state FROM recording_upload WHERE id=?",String.class,bytes(f.attempt))).isEqualTo("COMMITTED");
  assertThat(db.queryForObject("SELECT cloud_state FROM recording_asset WHERE user_id=? AND recording_id=?",String.class,bytes(f.owner),bytes(f.recording))).isEqualTo("STORED");
  assertThat(db.queryForObject("SELECT COUNT(*) FROM change_log WHERE user_id=? AND entity_type='RECORDING_ASSET'",Long.class,bytes(f.owner))).isEqualTo(1);
  var payload=new tools.jackson.databind.json.JsonMapper().readTree(db.queryForObject("SELECT payload FROM change_log WHERE user_id=?",String.class,bytes(f.owner)));
  assertThat(payload.path("generation").asString()).isEqualTo(UploadFinalization.finalKey(f.owner,f.recording,db.queryForObject("SELECT final_key FROM recording_upload WHERE id=?",String.class,bytes(f.attempt))).generation().toString());
  // Policy withdrawn after object write: fenced effects roll back; existing bytes/accounting stay intact.
  var other=fixture(db);var fin=new UploadFinalization(db,writer,other.clock);var pending=fin.prepare(other.lease,audio);
  db.update("DELETE FROM pin_slot WHERE user_id=?",bytes(other.owner));
  assertThatThrownBy(()->other.jobs.complete(other.lease,pending)).isInstanceOf(IllegalStateException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_asset WHERE user_id=?",Long.class,bytes(other.owner))).isZero();
  assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(other.owner))).isEqualTo(3);
  new UploadRecovery(db,new DataSourceTransactionManager(db.getDataSource()),other.clock).failed(other.lease,"NOT_CLOUD_TARGET");
 }
 public record Fixture(UUID owner,UUID recording,UUID attempt,JobQueue jobs,JobQueue.Lease lease,UploadApprovalDatabaseChecks.MutableClock clock){}
 public static Fixture fixture(JdbcTemplate db){
  var manager=new DataSourceTransactionManager(db.getDataSource());UUID owner=account(db),device=device(db,owner),recording=recording(db,owner,device,null,false,false,"VALIDATED");
  db.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,3,1000,'AAC_LC',48000,1,'VALIDATED')",bytes(recording),bytes(owner),"a".repeat(64));
  db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(recording));
  for(String table:List.of("user_sync_state","user_entitlement","storage_usage"))db.update("INSERT INTO "+table+"(user_id) VALUES(?)",bytes(owner));
  db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id,operation_id,requested_at) VALUES(?,1,?,?,CURRENT_TIMESTAMP)",bytes(owner),bytes(recording),bytes(UUID.randomUUID()));
  var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,device,UUID.randomUUID()));
  var clock=new UploadApprovalDatabaseChecks.MutableClock();var jobs=new JobQueue(db,access,manager,clock,Duration.ofMinutes(2),5);
  UUID attempt=new UploadReservations(db,access,manager,clock).reserve(account,new UploadReservations.Request(recording,3,"a".repeat(64),1)).attempt();
  db.update("UPDATE recording_upload SET state='VERIFYING' WHERE id=?",bytes(attempt));
  new org.springframework.transaction.support.TransactionTemplate(manager).executeWithoutResult(s->jobs.enqueue(account,JobQueue.Type.UPLOAD_VERIFY,attempt,attempt,"{}"));
  return new Fixture(owner,recording,attempt,jobs,jobs.claim(JobQueue.Type.UPLOAD_VERIFY).orElseThrow(),clock);
 }
}
