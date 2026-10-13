package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Real MySQL/FKs/triggers, isolated owners and actual private backup files; no user database. */
public final class AccountDeletionExecutionDatabaseChecks {
 private AccountDeletionExecutionDatabaseChecks(){}
 public static void verify(JdbcTemplate db)throws Exception{
  var tx=new DataSourceTransactionManager(db.getDataSource());var clock=new MovingClock();
  var registrations=new AccountRegistrationService(db,tx,clock);
  var ia=new VerifiedProviderIdentity("GOOGLE","p23-execution-a-"+UUID.randomUUID());var ib=new VerifiedProviderIdentity("KAKAO","p23-execution-b-"+UUID.randomUUID());
  var a=registrations.register(ia,null,"synthetic A");var b=registrations.register(ib,null,"synthetic B");
  var sessions=new SessionService(db,tx,clock,Duration.ofMinutes(15),Duration.ofDays(30));var tokens=sessions.issue(a);var bt=sessions.issue(b);
  var access=new AccountAccess(sessions);var deletion=new AccountDeletion(db,access,(provider,proof,nonce,started)->ia,new IdempotentMutations(db,access,tx,clock),tx,clock);
  for(var user:List.of(a,b)){
   var song=RetentionCandidateDatabaseChecks.song(db,user.userId());var recording=RetentionCandidateDatabaseChecks.recording(db,user.userId(),user.deviceId(),song,true,true,"VALIDATED");
   db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(recording),bytes(song));
   db.update("UPDATE recording SET condition_code='GOOD',revision=revision+1 WHERE id=?",bytes(recording));
   // History archives the prior non-null value; the first selection creates none.
   db.update("UPDATE recording SET condition_code='NORMAL',revision=revision+1 WHERE id=?",bytes(recording));
   assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE recording_id=?",Long.class,bytes(recording))).isEqualTo(1);
   db.update("UPDATE storage_usage SET used_bytes=6291456 WHERE user_id=?",bytes(user.userId()));
   var at=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC);
   db.update("INSERT INTO snapshot_header(id,user_id,op_id,purpose,status,schema_version,active_slot,reserved_bytes,attempt_id,build_started_at,lease_until) VALUES(?,?,?,'SYNC','BUILDING',13,0,100,?,?,?)",bytes(UUID.randomUUID()),bytes(user.userId()),bytes(UUID.randomUUID()),bytes(UUID.randomUUID()),at,at.plusMinutes(5));
  }
  db.update("UPDATE global_storage_usage SET used_bytes=12582912 WHERE id=1");
  var root=Files.createTempDirectory("song-record-p23-mysql-owned-").toRealPath();var ledger=Files.createDirectory(root.resolve("ledger"));var backups=Files.createDirectory(root.resolve("backups"));
  var json=new tools.jackson.databind.json.JsonMapper();Files.writeString(backups.resolve(".catalog.json"),json.writeValueAsString(Map.of("schema",1,"format","song-record-operational-backups-v1","environment","dev","retention_days",7,"authoritative",true,"instance_id",UUID.randomUUID().toString())));
  var artifacts=new PrivateDeletionArtifacts(ledger,backups);
  try{
   String auth="Bearer "+tokens.accessToken(),device=a.deviceId().toString();var challenge=deletion.challenge(auth,device,"GOOGLE");var prepared=deletion.prepare(auth,device,(String)challenge.get("challenge_id"),"synthetic verified proof");
   var body=json.writeValueAsString(Map.of("preparation_id",prepared.get("preparation_id"),"reauth_proof",prepared.get("reauth_proof"),"base_revision",prepared.get("base_revision"),"scope","ALL_ACCOUNT_DATA","confirmed",true));
   deletion.accept(auth,device,UUID.randomUUID().toString(),(String)prepared.get("status_token"),body);
   var keys=new HashSet<>(List.of(a.userId(),b.userId()));var jobs=new JobQueue(db,access,tx,clock,Duration.ofMinutes(2),5);
   var worker=new AccountDeletionWorker(db,tx,jobs,(owner,fence)->{assertThat(owner).isEqualTo(a.userId());fence.run();keys.remove(owner);},artifacts,clock);
   assertThat(worker.runOnce()).isTrue();assertThat(keys).contains(a.userId());clock.at=clock.at.plusSeconds(121);assertThat(worker.runOnce()).isTrue();
   assertThat(deletion.status((String)prepared.get("preparation_id"),(String)prepared.get("status_token"))).containsEntry("status","COMPLETED");
   assertThat(new DeletionDatabase(db).purged(a.userId())).isTrue();assertThat(keys).containsExactly(b.userId());
   assertThat(db.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(6291456);
   assertThat(db.queryForObject("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1",Long.class)).isEqualTo(100);
   sessions.authenticate(bt.accessToken(),b.deviceId());assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_file_spec WHERE user_id=?",Long.class,bytes(b.userId()))).isEqualTo(1);
   assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE user_id=?",Long.class,bytes(b.userId()))).isGreaterThan(0);
   assertThat(artifacts.blocksRestore(a.userId())).isTrue();assertThat(artifacts.blocksRestore(b.userId())).isFalse();
   var proofs=new DeletionDeviceProofs(db,clock);assertThat(proofs.confirm(a.userId().toString(),device,tokens.refreshToken())).containsEntry("deletion_confirmed",true);
   assertThatThrownBy(()->proofs.confirm(b.userId().toString(),device,tokens.refreshToken())).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
   assertThat(worker.runOnce()).isFalse();assertThat(db.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(6291456);
  }finally{if(!root.getParent().equals(Path.of(System.getProperty("java.io.tmpdir")).toRealPath()))throw new IllegalStateException("TEST_ROOT_CHANGED");try(var paths=Files.walk(root)){for(var path:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(path);}}
 }
 public static final class MovingClock extends Clock {public Instant at=Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS);public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId zone){return this;}public Instant instant(){return at;}}
}
