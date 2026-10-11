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
  s.f.jdbc.execute("CREATE TABLE playlist_item(id BINARY(16) PRIMARY KEY,user_id BINARY(16),playlist_id BINARY(16),song_id BINARY(16))");
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
  s.f.jdbc.update("INSERT INTO playlist_item VALUES(?,?,?,NULL)",bytes(item),bytes(s.f.registration.userId()),bytes(id));
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
}
