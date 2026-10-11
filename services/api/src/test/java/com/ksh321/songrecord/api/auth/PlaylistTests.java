package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.playlists.*;
import com.ksh321.songrecord.api.jobs.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.mock.web.MockHttpServletResponse;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
class PlaylistTests {
 final tools.jackson.databind.json.JsonMapper json=new tools.jackson.databind.json.JsonMapper();
 final SongCreationTests s=new SongCreationTests();
 @BeforeEach void open() throws Exception {
  s.setup();s.f.jdbc.execute("ALTER TABLE playlist ALTER COLUMN name VARCHAR(200)");s.f.jdbc.execute("ALTER TABLE playlist ADD created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
  s.f.jdbc.execute("ALTER TABLE deletion_ledger ADD id BINARY(16)");s.f.jdbc.execute("ALTER TABLE deletion_ledger ADD purged_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
  s.f.jdbc.execute("CREATE UNIQUE INDEX playlist_proof ON deletion_ledger(user_id,entity_type,entity_id)");
  s.f.jdbc.execute("CREATE TABLE playlist_item(id BINARY(16) PRIMARY KEY,user_id BINARY(16),playlist_id BINARY(16),song_id BINARY(16),candidate_brand VARCHAR(2),candidate_number VARCHAR(20),candidate_snapshot JSON,entry_key VARCHAR(64),position BIGINT,hidden_by_batch_id BINARY(16),created_at TIMESTAMP(3),updated_at TIMESTAMP(3),UNIQUE(playlist_id,entry_key))");
  // H2 binds JSON strings as JSON string values, unlike MySQL's object input.
  // Mirror MySQL getString here; real JSON + P04 triggers are checked in CI below.
  s.f.jdbc.execute("ALTER TABLE playlist_item ALTER COLUMN candidate_snapshot VARCHAR(4000)");
  new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(s.f.keeper);
 }
 @AfterEach void close()throws Exception{s.close();}
 MockHttpServletResponse write(String method,UUID id,String body,String op)throws Exception{
  var r=switch(method){case "POST"->post("/v1/playlists");case "PATCH"->patch("/v1/playlists/"+id);default->delete("/v1/playlists/"+id);};
  return s.mvc.perform(r.header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();
 }
 MockHttpServletResponse create(UUID id,String name)throws Exception{return write("POST",id,json.writeValueAsString(Map.of("id",id.toString(),"name",name)),UUID.randomUUID().toString());}
 long count(String table){return s.f.jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Long.class);}
 @Test void duplicateNamesTodayPersistenceRevisionAndPaging()throws Exception{
  UUID a=UUID.randomUUID(),b=UUID.randomUUID();assertThat(create(a," 오늘 ").getStatus()).isEqualTo(201);assertThat(create(b,"오늘").getStatus()).isEqualTo(201);
  assertThat(create(a,"overwrite").getContentAsString()).contains("오늘").doesNotContain("overwrite");
  var list=s.mvc.perform(get("/v1/playlists").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).param("limit","1")).andReturn().getResponse();
  assertThat(list.getStatus()).isEqualTo(200);String cursor=json.readTree(list.getContentAsString()).get("next_cursor").asText();
  assertThat(write("PATCH",a,"{\"base_revision\":1,\"name\":\"오늘\"}",UUID.randomUUID().toString()).getStatus()).isEqualTo(200);
  assertThat(write("PATCH",a,"{\"base_revision\":1,\"name\":\"stale\"}",UUID.randomUUID().toString()).getContentAsString()).contains("REVISION_CONFLICT");
  assertThat(s.mvc.perform(get("/v1/playlists").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).param("limit","1").param("cursor",cursor)).andReturn().getResponse().getContentAsString()).contains("LIST_CURSOR_EXPIRED");
 }
 @Test void deleteReplayCleanupPreservesSongsAndPermanentProof()throws Exception{
  assertThat(s.postBody(s.f.key,s.body("")).getStatus()).isEqualTo(201);
  UUID recording=UUID.randomUUID();
  s.f.jdbc.update("INSERT INTO recording(id,user_id,song_id,revision,lifecycle_state) VALUES(?,?,?,1,'ACTIVE')",bytes(recording),bytes(s.f.registration.userId()),bytes(s.id));
  var songsBefore=s.f.jdbc.queryForList("SELECT * FROM song");
  var recordingsBefore=s.f.jdbc.queryForList("SELECT * FROM recording");
  UUID id=UUID.randomUUID(),item=UUID.randomUUID();assertThat(create(id,"오늘").getStatus()).isEqualTo(201);
  s.f.jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id) VALUES(?,?,?,NULL)",bytes(item),bytes(s.f.registration.userId()),bytes(id));
  String op=UUID.randomUUID().toString(),body="{\"base_revision\":1}";
  var first=write("DELETE",id,body,op);assertThat(first.getStatus()).isEqualTo(200);assertThat(first.getContentAsString()).contains("DELETED").doesNotContain("name");
  assertThat(write("DELETE",id,body,op).getContentAsString()).isEqualTo(first.getContentAsString());
  assertThat(write("DELETE",id,body,UUID.randomUUID().toString()).getContentAsString()).isEqualTo(first.getContentAsString());
  var jobs=s.context.getBean(JobQueue.class);assertThat(new PlaylistCleanup(new JobRunner(jobs),s.f.jdbc).runOnce()).isTrue();
  assertThat(count("playlist")).isZero();assertThat(count("playlist_item")).isZero();
  assertThat(s.f.jdbc.queryForList("SELECT * FROM song")).usingRecursiveComparison().isEqualTo(songsBefore);
  assertThat(s.f.jdbc.queryForList("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(recordingsBefore);
  assertThat(write("DELETE",id,body,UUID.randomUUID().toString()).getContentAsString()).isEqualTo(first.getContentAsString());
  assertThat(write("PATCH",id,"{\"base_revision\":2,\"name\":\"revive\"}",UUID.randomUUID().toString()).getContentAsString()).contains("PLAYLIST_DELETED");
  assertThat(create(id,"revive").getContentAsString()).contains("RESOURCE_PURGED");assertThat(count("deletion_ledger")).isEqualTo(2);
 }
 @Test void validationAuthenticationAndForeignAccountAreRejected()throws Exception{
  UUID id=UUID.randomUUID();for(String name:List.of(" ","x".repeat(101)))assertThat(create(id,name).getStatus()).isEqualTo(400);
  assertThat(create(id,"😀".repeat(100)).getStatus()).isEqualTo(201);
  assertThat(s.mvc.perform(get("/v1/playlists")).andReturn().getResponse().getStatus()).isEqualTo(401);
  var p=s.f.other.principal();var tokens=s.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
  assertThat(s.mvc.perform(patch("/v1/playlists/"+id).header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content("{\"base_revision\":1,\"name\":\"other\"}")).andReturn().getResponse().getStatus()).isEqualTo(404);
 }
 MockHttpServletResponse add(UUID playlist,UUID song,long base,String op)throws Exception{return s.mvc.perform(post("/v1/playlists/"+playlist+"/items").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(Map.of("song_id",song.toString(),"base_revision",base)))).andReturn().getResponse();}
 @Test void registeredTjAndManualEntriesReuseCanonicalPositionWithoutRevisionBump()throws Exception{
  assertThat(s.postBody(s.f.key,s.body("")).getStatus()).isEqualTo(201);
  UUID p=UUID.randomUUID(),manual=UUID.randomUUID();assertThat(create(p,"등록곡").getStatus()).isEqualTo(201);
  s.f.jdbc.update("INSERT INTO song(id,user_id,source_type,tj_number,title,artist,version_code,lifecycle_state,revision) VALUES(?,?,'MANUAL',NULL,'직접 곡','직접 가수','NORMAL','ACTIVE',1)",bytes(manual),bytes(s.f.registration.userId()));
  String key=UUID.randomUUID().toString();var first=add(p,s.id,1,key);assertThat(first.getStatus()).isEqualTo(201);
  var receipt=json.readTree(first.getContentAsString());String item=receipt.get("item_id").asText();assertThat(receipt.get("items").get(0).get("entry_key").asText()).isEqualTo("tj:990001");
  assertThat(add(p,s.id,1,key).getContentAsString()).isEqualTo(first.getContentAsString());
  long seq=s.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(s.f.registration.userId()));
  var repeated=add(p,s.id,2,UUID.randomUUID().toString());assertThat(repeated.getStatus()).isEqualTo(200);
  var duplicate=json.readTree(repeated.getContentAsString());assertThat(duplicate.get("created").asBoolean()).isFalse();assertThat(duplicate.get("item_id").asText()).isEqualTo(item);assertThat(duplicate.get("playlist").get("revision").asLong()).isEqualTo(2);assertThat(duplicate.get("items").get(0).get("position").asLong()).isZero();assertThat(count("playlist_item")).isEqualTo(1);
  assertThat(s.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(s.f.registration.userId()))).isEqualTo(seq);
  assertThat(add(p,manual,2,UUID.randomUUID().toString()).getContentAsString()).contains("manual:"+manual);assertThat(count("playlist_item")).isEqualTo(2);
  assertThat(add(p,s.id,1,UUID.randomUUID().toString()).getContentAsString()).contains("REVISION_CONFLICT");
 }
 @Test void foreignInactiveAndDeletedTargetsNeverAddAnItem()throws Exception{
  UUID p=UUID.randomUUID();create(p,"보존");s.postBody(s.f.key,s.body(""));
  assertThat(add(p,UUID.randomUUID(),1,UUID.randomUUID().toString()).getStatus()).isEqualTo(404);
  UUID foreign=UUID.randomUUID(),foreignList=UUID.randomUUID();
  s.f.jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,lifecycle_state,revision,updated_at) VALUES(?,?,'MANUAL','foreign','artist','NORMAL','ACTIVE',1,CURRENT_TIMESTAMP)",bytes(foreign),bytes(s.f.other.principal().userId()));
  s.f.jdbc.update("INSERT INTO playlist(id,user_id,name,revision,updated_at) VALUES(?,?,'foreign',1,CURRENT_TIMESTAMP)",bytes(foreignList),bytes(s.f.other.principal().userId()));
  assertThat(add(p,foreign,1,UUID.randomUUID().toString()).getStatus()).isEqualTo(404);
  assertThat(add(foreignList,s.id,1,UUID.randomUUID().toString()).getStatus()).isEqualTo(404);
  assertThat(count("playlist_item")).isZero();
  s.f.jdbc.update("UPDATE song SET lifecycle_state='TRASHED' WHERE id=?",bytes(s.id));assertThat(add(p,s.id,1,UUID.randomUUID().toString()).getContentAsString()).contains("SONG_NOT_ACTIVE");assertThat(count("playlist_item")).isZero();
  assertThat(write("DELETE",p,"{\"base_revision\":1}",UUID.randomUUID().toString()).getStatus()).isEqualTo(200);assertThat(add(p,s.id,1,UUID.randomUUID().toString()).getContentAsString()).contains("PLAYLIST_DELETED");assertThat(count("playlist_item")).isZero();
 }
 MockHttpServletResponse candidate(UUID p,String token,long revision,String op)throws Exception{
  return candidateBody(p,json.writeValueAsString(Map.of("source_token",token,"base_revision",revision)),op);
 }
 MockHttpServletResponse candidateBody(UUID p,String body,String op)throws Exception{
  return s.mvc.perform(post("/v1/playlists/"+p+"/items").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();
 }
 @Test void verifiedCandidateAndRegisteredSongShareOneStableEntry()throws Exception{
  UUID p=UUID.randomUUID();create(p,"후보");String op=UUID.randomUUID().toString();
  var first=candidate(p,"valid",1,op);assertThat(first.getStatus()).isEqualTo(201);
  var item=json.readTree(first.getContentAsString()).get("items").get(0);
  assertThat(item.get("song_id").isNull()).isTrue();assertThat(item.get("entry_key").asText()).isEqualTo("tj:990001");
  assertThat(item.get("candidate_snapshot").get("title").asText()).isEqualTo("원본 곡");
  assertThat(candidate(p,"valid",1,op).getContentAsString()).isEqualTo(first.getContentAsString());
  var duplicate=candidate(p,"valid",2,UUID.randomUUID().toString());assertThat(duplicate.getStatus()).isEqualTo(200);
  assertThat(json.readTree(duplicate.getContentAsString()).get("item_id")).isEqualTo(item.get("id"));
  s.postBody(s.f.key,s.body(""));var registered=add(p,s.id,2,UUID.randomUUID().toString());assertThat(registered.getStatus()).isEqualTo(200);
  assertThat(json.readTree(registered.getContentAsString()).get("item_id")).isEqualTo(item.get("id"));assertThat(count("playlist_item")).isEqualTo(1);
 }
 @Test void kyForgedAndClientOverriddenCandidatesLeaveItemsAndOrderUnchanged()throws Exception{
  UUID p=UUID.randomUUID();create(p,"보존");candidate(p,"valid",1,UUID.randomUUID().toString());
  var before=s.f.jdbc.queryForList("SELECT * FROM playlist_item");long receipts=count("mutation_receipt");
  var ky=candidate(p,"ky",2,UUID.randomUUID().toString());assertThat(ky.getStatus()).isEqualTo(400);assertThat(ky.getContentAsString()).contains("PLAYLIST_TJ_REQUIRED");
  assertThat(candidate(p,"forged",2,UUID.randomUUID().toString()).getStatus()).isEqualTo(400);
  assertThat(candidateBody(p,"{\"source_token\":\"valid\",\"base_revision\":2,\"entry_key\":\"tj:999\"}",UUID.randomUUID().toString()).getStatus()).isEqualTo(400);
  assertThat(candidateBody(p,"{\"base_revision\":2,\"title\":\"manual candidate\"}",UUID.randomUUID().toString()).getStatus()).isEqualTo(400);
  assertThat(s.f.jdbc.queryForList("SELECT * FROM playlist_item")).usingRecursiveComparison().isEqualTo(before);
  assertThat(s.f.jdbc.queryForObject("SELECT revision FROM playlist WHERE id=?",Long.class,bytes(p))).isEqualTo(2);
  assertThat(count("mutation_receipt")).isEqualTo(receipts);
 }
}
