package com.ksh321.songrecord.api.auth;
import java.util.*;import java.time.*;import org.junit.jupiter.api.*;
import com.ksh321.songrecord.api.recordings.*;import com.ksh321.songrecord.api.retention.CleanupObjects;import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import static org.assertj.core.api.Assertions.*;import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
class TrashPurgeTests {
 final TrashRestorationTests r=new TrashRestorationTests();boolean exists=true,failDelete;com.ksh321.songrecord.api.jobs.JobQueue jobs;PurgeWorker worker;
 @BeforeEach void open()throws Exception{
  r.open();var f=r.f;f.f.jdbc.execute("ALTER TABLE deletion_ledger ADD id BINARY(16)");f.f.jdbc.execute("ALTER TABLE deletion_ledger ADD purged_at TIMESTAMP(3)");f.f.jdbc.execute("ALTER TABLE recording_asset ADD created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
  UUID generation=uuid(f.f.jdbc.queryForObject("SELECT generation FROM recording_asset",byte[].class));f.f.jdbc.update("UPDATE recording_asset SET object_key=?",new StorageObjectKeys.Final(f.owner(),f.recording,generation).value());f.f.jdbc.update("UPDATE storage_usage SET used_bytes=1234 WHERE user_id=?",bytes(f.owner()));f.f.jdbc.update("UPDATE global_storage_usage SET used_bytes=1234");
  jobs=f.s.context.getBean(com.ksh321.songrecord.api.jobs.JobQueue.class);worker=new PurgeWorker(f.f.jdbc,f.f.manager,jobs,new CleanupObjects(){public boolean existsFinal(StorageObjectKeys.Final key){return exists;}public void deleteFinal(StorageObjectKeys.Final key)throws Exception{if(failDelete)throw new java.io.IOException("synthetic failure");exists=false;}},f.f.clock);
 }
 @AfterEach void close()throws Exception{r.close();}
 org.springframework.mock.web.MockHttpServletResponse purge(String batch,String op,String body)throws Exception{var f=r.f;return f.s.mvc.perform(post("/v1/trash/"+batch+"/purge").header("Authorization","Bearer "+f.f.tokens.accessToken()).header("X-Device-Id",f.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();}
 @Test void physicalFailureKeepsPendingBytesThenRetryDebitsOnceAndReleasesKeys()throws Exception{
  var f=r.f;String batch=r.batch("SONG_AND_RECORDINGS"),op=UUID.randomUUID().toString();var reply=purge(batch,op,"{\"base_revision\":1}");assertThat(reply.getStatus()).isEqualTo(202);assertThat(purge(batch,op,"{\"base_revision\":1}").getContentAsString()).isEqualTo(reply.getContentAsString());assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("PURGE_PENDING");
  failDelete=true;assertThat(worker.runOnce()).isTrue();assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isEqualTo(1234);assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger",Integer.class)).isZero();
  failDelete=false;f.f.clock.instant=f.f.clock.instant.plusSeconds(10);var retry=jobs.claim(com.ksh321.songrecord.api.jobs.JobQueue.Type.ENTITY_PURGE).orElseThrow();assertThat(jobs.complete(retry,worker.prepare(retry))).isTrue();assertThat(worker.runOnce()).isFalse();assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("PURGED");assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("PURGED");assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isZero();assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist_item",Integer.class)).isZero();assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger WHERE entity_type='RECORDING_ASSET'",Integer.class)).isEqualTo(1);
 }
 @Test void songOnlyPurgeNeverTouchesRetainedRecordingOrFile()throws Exception{
  var f=r.f;String batch=r.batch("SONG_ONLY");assertThat(purge(batch,UUID.randomUUID().toString(),"{\"base_revision\":1}").getStatus()).isEqualTo(202);worker.runOnce();assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("PURGED");assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("ACTIVE");assertThat(f.f.jdbc.queryForObject("SELECT cloud_state FROM recording_asset",String.class)).isEqualTo("STORED");assertThat(exists).isTrue();assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isEqualTo(1234);
 }
 @Test void foreignSelectionAndStaleRevisionCannotFenceSubjects()throws Exception{
  var f=r.f;String batch=r.batch("SONG_AND_RECORDINGS");assertThat(purge(batch,UUID.randomUUID().toString(),"{\"base_revision\":1,\"item_ids\":[\""+UUID.randomUUID()+"\"]}").getStatus()).isEqualTo(400);assertThat(purge(batch,UUID.randomUUID().toString(),"{\"base_revision\":99}").getStatus()).isEqualTo(409);assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("TRASHED");
 }
 @Test void lostLeaseCannotDebitAndNewLeaseFinishesAbsentObjectOnce()throws Exception{
  var f=r.f;String batch=r.batch("SONG_AND_RECORDINGS");assertThat(purge(batch,UUID.randomUUID().toString(),"{\"base_revision\":1}").getStatus()).isEqualTo(202);
  var old=jobs.claim(com.ksh321.songrecord.api.jobs.JobQueue.Type.ENTITY_PURGE).orElseThrow();var effects=worker.prepare(old);assertThat(exists).isFalse();f.f.clock.instant=f.f.clock.instant.plusSeconds(181);assertThat(jobs.complete(old,effects)).isFalse();assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isEqualTo(1234);
  var next=jobs.claim(com.ksh321.songrecord.api.jobs.JobQueue.Type.ENTITY_PURGE).orElseThrow();assertThat(jobs.complete(next,worker.prepare(next))).isTrue();assertThat(f.f.jdbc.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isZero();assertThat(jobs.complete(old,effects)).isFalse();
 }
 @Test void expiryUsesServerTimeAndQueuesSameDurablePathOnce()throws Exception{
  var f=r.f;r.batch("SONG_AND_RECORDINGS");var service=new TrashPurge(f.f.jdbc,f.f.access,f.f.mutations,f.s.context.getBean(com.ksh321.songrecord.api.sync.AccountChanges.class),jobs,f.s.context.getBean(RecordingEditing.class),f.f.clock);
  assertThat(service.expire()).isZero();f.f.clock.instant=Instant.parse("2026-12-01T00:00:00Z");assertThat(service.expire()).isEqualTo(1);assertThat(service.expire()).isZero();assertThat(worker.runOnce()).isTrue();assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("PURGED");
 }
}
