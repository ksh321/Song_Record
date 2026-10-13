package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.account.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

public class AccountDeletionWorkerTests {
 final AccountDeletionTests f=new AccountDeletionTests();@TempDir Path root;
 JobQueue jobs;PrivateDeletionArtifacts artifacts;AccountDeletionWorker worker;Map<String,Object> preparation;
 UUID owner,other;boolean objectsFail;int objectCalls;Path backupA,backupB;
 @BeforeEach void open()throws Exception{
  f.open();var db=f.f.jdbc;owner=f.f.registration.userId();other=f.f.other.principal().userId();
  for(var column:List.of("attempt_count INT NOT NULL DEFAULT 0","lease_token BINARY(16)","claimed_at TIMESTAMP(3)","lease_until TIMESTAMP(3)","last_error VARCHAR(512)","finished_at TIMESTAMP(3)","revision BIGINT NOT NULL DEFAULT 1"))db.execute("ALTER TABLE job ADD "+column);
  db.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,used_bytes BIGINT,reserved_bytes BIGINT,revision BIGINT,updated_at TIMESTAMP(3))");
  db.execute("INSERT INTO global_storage_usage VALUES(1,90,30,1,CURRENT_TIMESTAMP)");
  db.execute("CREATE TABLE snapshot_capacity(id INT PRIMARY KEY,reserved_bytes BIGINT)");db.execute("INSERT INTO snapshot_capacity VALUES(1,0)");
  db.execute("CREATE TABLE snapshot_header(id BINARY(16) PRIMARY KEY,user_id BINARY(16),status VARCHAR(16),active_slot INT,lease_until TIMESTAMP(3), FOREIGN KEY(user_id) REFERENCES app_user(id))");
  db.execute("CREATE TABLE song(id BINARY(16) PRIMARY KEY,user_id BINARY(16),representative_recording_id BINARY(16),revision BIGINT,updated_at TIMESTAMP(3), FOREIGN KEY(user_id) REFERENCES app_user(id))");
  db.execute("CREATE TABLE recording(id BINARY(16) PRIMARY KEY,user_id BINARY(16),song_id BINARY(16),lifecycle_state VARCHAR(16),deleted_at TIMESTAMP(3),revision BIGINT,updated_at TIMESTAMP(3),FOREIGN KEY(song_id) REFERENCES song(id),FOREIGN KEY(user_id) REFERENCES app_user(id))");
  db.execute("CREATE TABLE recording_upload(id BINARY(16),user_id BINARY(16),expires_at TIMESTAMP(3))");
  db.update("UPDATE storage_usage SET used_bytes=40,reserved_bytes=10 WHERE user_id=?",bytes(owner));db.update("UPDATE storage_usage SET used_bytes=50,reserved_bytes=20 WHERE user_id=?",bytes(other));
  for(var user:List.of(owner,other)){var song=UUID.randomUUID();var recording=UUID.randomUUID();db.update("INSERT INTO song VALUES(?,?,?,1,?)",bytes(song),bytes(user),null,stamp());db.update("INSERT INTO recording VALUES(?,?,?,'ACTIVE',NULL,1,?)",bytes(recording),bytes(user),bytes(song),stamp());db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(recording),bytes(song));}
  var ledger=Files.createDirectory(root.resolve("ledger"));var backups=Files.createDirectory(root.resolve("backups"));catalog(backups);artifacts=new PrivateDeletionArtifacts(ledger,backups);
  backupA=backup(backups,List.of(owner));backupB=backup(backups,List.of(other));
  jobs=new JobQueue(db,f.f.access,f.f.manager,f.f.clock,Duration.ofMinutes(2),5);
  worker=new AccountDeletionWorker(db,f.f.manager,jobs,(id,fence)->{assertThat(id).isEqualTo(owner);com.ksh321.songrecord.api.locking.LockOrder.requireOutsideTransaction();fence.run();objectCalls++;if(objectsFail)throw new java.io.IOException("synthetic unavailable");},artifacts,f.f.clock);
  preparation=f.prepare();f.service.accept(f.auth,f.device,UUID.randomUUID().toString(),(String)preparation.get("status_token"),f.body(preparation));
 }
 @AfterEach void close()throws Exception{f.close();}
 static void catalog(Path backups)throws Exception{Files.writeString(backups.resolve(".catalog.json"),new tools.jackson.databind.json.JsonMapper().writeValueAsString(Map.of("schema",1,"format","song-record-operational-backups-v1","environment","dev","retention_days",7,"authoritative",true,"instance_id",UUID.randomUUID().toString())));}
 static Path backup(Path backups,List<UUID> subjects)throws Exception{var id=UUID.randomUUID();var dir=Files.createDirectory(backups.resolve(id.toString()));var payload="synthetic backup".getBytes(java.nio.charset.StandardCharsets.UTF_8);Files.write(dir.resolve("payload.zip"),payload);Files.writeString(dir.resolve("manifest.json"),new tools.jackson.databind.json.JsonMapper().writeValueAsString(Map.of("schema",1,"artifact_id",id.toString(),"subjects",subjects.stream().map(UUID::toString).toList(),"created_at","2026-01-01T00:00:00Z","sha256",HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(payload)))));return dir;}
 void advance(long seconds){f.f.clock.instant=f.f.clock.instant.plusSeconds(seconds);}
 Map<String,Object> status(){return f.service.status((String)preparation.get("preparation_id"),(String)preparation.get("status_token"));}
 LocalDateTime stamp(){return LocalDateTime.ofInstant(f.f.clock.instant,ZoneOffset.UTC);}
 void verifyOtherLogin(){assertThat(f.f.jdbc.queryForObject("SELECT revoked_at FROM auth_session WHERE id=?",java.sql.Timestamp.class,bytes(f.f.other.principal().sessionId()))).isNull();var registration=new AccountRegistrationService(f.f.jdbc,f.f.manager,f.f.clock).register(new VerifiedProviderIdentity("KAKAO","b"),f.f.other.principal().deviceId(),"fixture B");assertThat(registration.userId()).isEqualTo(other);var fresh=f.f.sessions.issue(registration);f.f.sessions.authenticate(fresh.accessToken(),registration.deviceId());}
 @Test void durableDrainRetryPrivateDatabaseAndSharedBackupConfirmationPreserveOtherAccount()throws Exception{
  assertThat(worker.runOnce()).isTrue();assertThat(status()).containsEntry("status","DELETING");assertThat(objectCalls).isZero();assertThat(artifacts.blocksRestore(owner)).isTrue();assertThat(artifacts.blocksRestore(other)).isFalse();
  advance(121);objectsFail=true;worker.runOnce();assertThat(status()).containsEntry("retrying",true);assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(90);
  var mixed=backup(root.resolve("backups"),List.of(owner,other));objectsFail=false;advance(6);worker.runOnce();
  assertThat(status()).containsEntry("status","BACKUP_CLEANUP").containsEntry("retrying",false);assertThat(new DeletionDatabase(f.f.jdbc).purged(owner)).isTrue();
  assertThat(Files.exists(backupA)).isFalse();assertThat(Files.exists(backupB.resolve("payload.zip"))).isTrue();assertThat(Files.exists(mixed.resolve("payload.zip"))).isTrue();
  assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(50);assertThat(f.f.jdbc.queryForObject("SELECT reserved_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(20);f.f.access.revalidate(f.f.other);
  var proofs=new DeletionDeviceProofs(f.f.jdbc,f.f.clock);assertThat(proofs.confirm(owner.toString(),f.device,f.f.tokens.refreshToken())).containsOnlyKeys("deletion_confirmed");assertThatThrownBy(()->proofs.confirm(other.toString(),f.device,f.f.tokens.refreshToken())).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
  advance(8*86400);worker.runOnce();assertThat(status()).containsEntry("status","BACKUP_CLEANUP").containsEntry("retrying",true).containsEntry("completed_at",null);
  // Simulated retention publisher physically retires the shared fixture; B's separate copy remains.
  Files.delete(mixed.resolve("payload.zip"));Files.delete(mixed.resolve("manifest.json"));Files.delete(mixed);advance(3601);worker.runOnce();
  assertThat(status()).containsEntry("status","COMPLETED").containsEntry("retrying",false);assertThat(status().get("completed_at")).isNotNull();
  assertThat(worker.runOnce()).isFalse();assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(50);assertThat(artifacts.blocksRestore(owner)).isTrue();
  advance(22*86400);assertThat(worker.retireCompleted()).isEqualTo(1);assertThat(artifacts.blocksRestore(owner)).isFalse();var b=new AccountRegistrationService(f.f.jdbc,f.f.manager,f.f.clock).register(new VerifiedProviderIdentity("KAKAO","b"),f.f.other.principal().deviceId(),"fixture B");assertThat(b.userId()).isEqualTo(other);var fresh=f.f.sessions.issue(b);f.f.sessions.authenticate(fresh.accessToken(),b.deviceId());
  assertThat(Files.exists(backupB.resolve("payload.zip"))).isTrue();assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger WHERE user_id=?",Long.class,bytes(owner))).isZero();
 }
 @Test void objectFailureBudgetStopsWithoutPretendingCompletionOrTouchingAnotherOwner()throws Exception{
  worker.runOnce();advance(121);objectsFail=true;for(int i=0;i<5;i++){worker.runOnce();advance(301);}
  assertThat(status()).containsEntry("status","DELETING").containsEntry("retrying",true).containsEntry("completed_at",null);
  assertThat(f.f.jdbc.queryForObject("SELECT state FROM job WHERE type='ACCOUNT_DELETE'",String.class)).isEqualTo("FAILED");assertThat(artifacts.blocksRestore(owner)).isTrue();assertThat(Files.exists(backupA.resolve("payload.zip"))).isTrue();verifyOtherLogin();
 }
 @Test void unreviewedOwnerTableAndMissingBackupAuthorityFailClosed()throws Exception{
  assertThatThrownBy(()->new PrivateDeletionArtifacts(Files.createDirectory(root.resolve("new-ledger")),Files.createDirectory(root.resolve("unregistered-backups")))).isInstanceOf(java.io.IOException.class);
  worker.runOnce();advance(121);f.f.jdbc.execute("CREATE TABLE unreviewed_owner_table(user_id BINARY(16))");worker.runOnce();assertThat(status().get("completed_at")).isNull();assertThat(new DeletionDeviceProofs(f.f.jdbc,f.f.clock).confirm(owner.toString(),f.device,f.f.tokens.refreshToken())).containsEntry("deletion_confirmed",true);f.f.access.revalidate(f.f.other);
 }
 public static void verifyReal(com.ksh321.songrecord.api.storage.R2Storage storage,java.util.function.Consumer<com.ksh321.songrecord.api.storage.StorageObjectKeys.Temporary> seedTemporary)throws Exception{
  var f=new AccountDeletionWorkerTests();f.root=Files.createTempDirectory("song-record-p23-r2-owned-").toRealPath();
  boolean createdA=false,createdB=false;com.ksh321.songrecord.api.storage.StorageObjectKeys.Final keyA=null,keyB=null;
  try{f.open();var recording=UUID.randomUUID();keyA=new com.ksh321.songrecord.api.storage.StorageObjectKeys.Final(f.owner,recording,UUID.randomUUID());keyB=new com.ksh321.songrecord.api.storage.StorageObjectKeys.Final(f.other,UUID.randomUUID(),UUID.randomUUID());
   if(storage.existsFinal(keyA)||storage.existsFinal(keyB))throw new IllegalStateException("PROBE_COLLISION");
   byte[] a=new byte[40],b=new byte[50];Arrays.fill(a,(byte)1);Arrays.fill(b,(byte)2);
   createdA=true;storage.ensureFinal(keyA,java.nio.ByteBuffer.wrap(a),HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(a)));
   createdB=true;storage.ensureFinal(keyB,java.nio.ByteBuffer.wrap(b),HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(b)));
   seedTemporary.accept(new com.ksh321.songrecord.api.storage.StorageObjectKeys.Temporary(f.owner,recording,UUID.randomUUID()));
   var worker=new AccountDeletionWorker(f.f.f.jdbc,f.f.f.manager,f.jobs,storage,f.artifacts,f.f.f.clock);
   assertThat(worker.runOnce()).isTrue();f.advance(121);assertThat(worker.runOnce()).isTrue();
   assertThat(storage.existsFinal(keyA)).isFalse();assertThat(storage.existsFinal(keyB)).isTrue();assertThat(f.status()).containsEntry("status","COMPLETED");
   assertThat(new DeletionDatabase(f.f.f.jdbc).purged(f.owner)).isTrue();assertThat(Files.exists(f.backupA)).isFalse();assertThat(Files.exists(f.backupB.resolve("payload.zip"))).isTrue();assertThat(f.f.f.jdbc.queryForObject("SELECT used_bytes FROM global_storage_usage WHERE id=1",Long.class)).isEqualTo(50);
  }finally{
   if(createdA)storage.clearOwner(f.owner,()->{});
   if(createdB&&storage.existsFinal(keyB)){storage.deleteFinal(keyB);if(storage.existsFinal(keyB))throw new IllegalStateException("PROBE_CLEANUP_UNCONFIRMED");}
   if(f.f.f.keeper!=null)f.close();
   if(!f.root.getParent().equals(Path.of(System.getProperty("java.io.tmpdir")).toRealPath()))throw new IllegalStateException("TEST_ROOT_CHANGED");try(var paths=Files.walk(f.root)){for(var path:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(path);}
  }
 }
}
