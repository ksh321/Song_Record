package com.ksh321.songrecord.api.account;

import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import com.ksh321.songrecord.api.operations.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class DeletionObservationsTests {
 JdbcTemplate db;TransactionTemplate tx;OperationsRecorder recorder;
 UUID owner=UUID.randomUUID(),other=UUID.randomUUID(),song=UUID.randomUUID(),otherSong=UUID.randomUUID(),job=UUID.randomUUID();
 @BeforeEach void open(){
  var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");db=new JdbcTemplate(ds);var manager=new DataSourceTransactionManager(ds);tx=new TransactionTemplate(manager);recorder=new OperationsRecorder(db,manager);
  db.execute("CREATE TABLE app_user(id BINARY(16) PRIMARY KEY,status VARCHAR(16))");
  db.execute("CREATE TABLE job(id BINARY(16) PRIMARY KEY,user_id BINARY(16))");
  db.execute("CREATE TABLE song(id BINARY(16) PRIMARY KEY,user_id BINARY(16))");
  db.execute("CREATE TABLE operations_observation(id BINARY(16) PRIMARY KEY,actor_id BINARY(16),target_id BINARY(16),previous_target_id BINARY(16),job_id BINARY(16),attempt_count INT,actor_kind VARCHAR(16),action VARCHAR(32),result VARCHAR(32),status_code INT,duration_ms BIGINT,observed_at TIMESTAMP,sync_change_backlog BIGINT)");
  for(var user:List.of(owner,other))db.update("INSERT INTO app_user VALUES(?,'ACTIVE')",bytes(user));
  db.update("INSERT INTO song VALUES(?,?)",bytes(song),bytes(owner));db.update("INSERT INTO song VALUES(?,?)",bytes(otherSong),bytes(other));db.update("INSERT INTO job VALUES(?,?)",bytes(job),bytes(owner));
 }
 @AfterEach void close(){db.execute("SHUTDOWN");}
 UUID observation(UUID actor,UUID target,UUID previous,UUID work){var id=UUID.randomUUID();db.update("INSERT INTO operations_observation(id,actor_id,target_id,previous_target_id,job_id,actor_kind,action,result,status_code,duration_ms,observed_at) VALUES(?,?,?,?,?,'USER','OTHER','SUCCESS',200,1,CURRENT_TIMESTAMP)",bytes(id),bytes(actor),target==null?null:bytes(target),previous==null?null:bytes(previous),work==null?null:bytes(work));return id;}
 long references(){return db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE actor_id=? OR target_id=? OR previous_target_id=? OR job_id=?",Long.class,bytes(owner),bytes(song),bytes(song),bytes(job));}
 @Test void erasesOwnerAndWorkerReferencesButPreservesOtherAccountAndTransactionRollback(){
  observation(owner,song,null,null);observation(UUID.randomUUID(),song,null,job);
  var cross=observation(other,song,song,null);var keep=observation(other,otherSong,null,null);
  assertThatThrownBy(()->tx.execute(s->{new DeletionObservations(db,List.of("song")).beforePurge(owner);throw new IllegalStateException("synthetic rollback");})).isInstanceOf(IllegalStateException.class);
  assertThat(references()).isEqualTo(3);
  tx.executeWithoutResult(s->{var cleanup=new DeletionObservations(db,List.of("song"));cleanup.beforePurge(owner);
   // Simulate a trigger emitted by the owning purge itself.
   observation(owner,song,null,null);cleanup.clearDirect(owner);assertThat(cleanup.hasDirectReferences(owner)).isFalse();});
  assertThat(references()).isZero();assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation",Long.class)).isEqualTo(2);
  assertThat(db.queryForMap("SELECT target_id,previous_target_id FROM operations_observation WHERE id=?",bytes(cross))).containsEntry("TARGET_ID",null).containsEntry("PREVIOUS_TARGET_ID",null);
  assertThat((byte[])db.queryForMap("SELECT target_id FROM operations_observation WHERE id=?",bytes(keep)).get("TARGET_ID")).isEqualTo(bytes(otherSong));
 }
 @Test void lateHttpAndJobEventsCannotReintroduceDeletedOwnerIdentifiers() throws Exception {
  var began=new CountDownLatch(1);
  try(var pool=Executors.newSingleThreadExecutor()){
   var pending=tx.execute(s->{db.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));
    var future=pool.submit(()->{began.countDown();recorder.record(owner,song,"USER",OperationsContext.Action.SONG_READ,OperationsContext.Result.SUCCESS,200,1,Instant.now());});
    try{assertThat(began.await(5,TimeUnit.SECONDS)).isTrue();}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException(e);}
    new DeletionObservations(db,List.of("song")).beforePurge(owner);db.update("DELETE FROM song WHERE user_id=?",bytes(owner));db.update("DELETE FROM app_user WHERE id=?",bytes(owner));return future;});
   pending.get(10,TimeUnit.SECONDS);
  }
  recorder.job(new JobQueue.Observation(UUID.randomUUID(),job,song,1,OperationsContext.Action.JOB_SUCCESS,Instant.now()));
  assertThat(references()).isZero();assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE actor_kind='ANONYMOUS' AND actor_id IS NULL AND target_id IS NULL",Long.class)).isEqualTo(1);
 }
 @Test void anonymousAndFailedRequestsDoNotPersistUnverifiedPathTargets(){
  recorder.record(null,song,"ANONYMOUS",OperationsContext.Action.OTHER,OperationsContext.Result.SUCCESS,200,1,Instant.now());
  recorder.record(other,song,"USER",OperationsContext.Action.OTHER,OperationsContext.Result.NOT_FOUND,404,1,Instant.now());
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE target_id IS NOT NULL",Long.class)).isZero();
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation WHERE actor_id=?",Long.class,bytes(other))).isEqualTo(1);
 }
}
