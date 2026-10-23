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
  s.setup();s.f.jdbc.execute("ALTER TABLE playlist ALTER COLUMN name VARCHAR(200)");
  s.f.jdbc.execute("ALTER TABLE deletion_ledger ADD id BINARY(16)");s.f.jdbc.execute("ALTER TABLE deletion_ledger ADD purged_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
  s.f.jdbc.execute("CREATE UNIQUE INDEX playlist_proof ON deletion_ledger(user_id,entity_type,entity_id)");
  new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(s.f.keeper);
 }
 @Test void iconCreateRenameAndReplayPreserveTheSelectedIcon()throws Exception{
  UUID id=UUID.randomUUID();String op=UUID.randomUUID().toString();
  String body=json.writeValueAsString(Map.of("id",id.toString(),"name","아이콘 목록","icon","heart"));
  var first=s.mvc.perform(post("/v1/playlists").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();
  assertThat(first.getStatus()).isEqualTo(201);assertThat(json.readTree(first.getContentAsString()).get("icon").asText()).isEqualTo("heart");
  var replay=s.mvc.perform(post("/v1/playlists").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();
  assertThat(replay.getContentAsString()).isEqualTo(first.getContentAsString());
  var changed=s.mvc.perform(patch("/v1/playlists/"+id).header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID().toString()).contentType("application/json").content(json.writeValueAsString(Map.of("name","새 이름","base_revision",1)))).andReturn().getResponse();
  assertThat(changed.getStatus()).isEqualTo(200);assertThat(json.readTree(changed.getContentAsString()).get("icon").asText()).isEqualTo("heart");
 }
 @Test void libraryOrderIsAtomicReplayedAndRejectsStaleOrIncompleteMembership()throws Exception{
  UUID a=UUID.randomUUID(),b=UUID.randomUUID();create(a,"첫 목록");create(b,"둘째 목록");
  String op=UUID.randomUUID().toString();
  String body=json.writeValueAsString(Map.of("base_revision",1,"ordered_playlists",List.of(Map.of("id",b.toString(),"base_revision",1),Map.of("id",a.toString(),"base_revision",1))));
  var service=s.context.getBean(PlaylistService.class);String auth="Bearer "+s.f.tokens.accessToken(),device=s.f.registration.deviceId().toString();
  assertThat(s.mvc.perform(put("/v1/playlists/"+a+"/library-order").contentType("application/json").content(body)).andReturn().getResponse().getStatus()).isEqualTo(401);
  var http=s.mvc.perform(put("/v1/playlists/"+a+"/library-order").header("Authorization",auth).header("X-Device-Id",device).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();
  assertThat(http.getStatus()).isEqualTo(200);assertThat(http.getHeader("Cache-Control")).isEqualTo("no-store");
  var reply=service.reorderLibrary(auth,device,op,a.toString(),body);
  assertThat(reply.body()).isEqualTo(http.getContentAsString());
  var result=json.readTree(reply.body());assertThat(reply.status()).isEqualTo(200);
  assertThat(result.get("playlists").get(0).get("id").asText()).isEqualTo(b.toString());
  assertThat(result.get("playlists").get(0).get("display_order").asLong()).isZero();
  assertThat(result.get("playlists").get(1).get("display_order").asLong()).isEqualTo(1);
  assertThat(result.get("playlist").get("revision").asLong()).isEqualTo(2);
  assertThat(service.reorderLibrary(auth,device,op,a.toString(),body).body()).isEqualTo(reply.body());
  var before=s.f.jdbc.queryForList("SELECT id,name,icon,display_order,revision FROM playlist ORDER BY id");
  assertThatThrownBy(()->service.reorderLibrary(auth,device,UUID.randomUUID().toString(),a.toString(),body)).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
  String omitted=json.writeValueAsString(Map.of("base_revision",2,"ordered_playlists",List.of(Map.of("id",a.toString(),"base_revision",2))));
  assertThatThrownBy(()->service.reorderLibrary(auth,device,UUID.randomUUID().toString(),a.toString(),omitted)).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
  String foreign=json.writeValueAsString(Map.of("base_revision",2,"ordered_playlists",List.of(Map.of("id",a.toString(),"base_revision",2),Map.of("id",UUID.randomUUID().toString(),"base_revision",2))));
  assertThatThrownBy(()->service.reorderLibrary(auth,device,UUID.randomUUID().toString(),a.toString(),foreign)).isInstanceOf(com.ksh321.songrecord.api.web.ApiException.class);
  assertThat(s.f.jdbc.queryForList("SELECT id,name,icon,display_order,revision FROM playlist ORDER BY id")).usingRecursiveComparison().isEqualTo(before);
 }
 @Test void removingOneItemPreservesOtherListsSongsAndRecordings()throws Exception{
  s.postBody(s.f.key,s.body(""));UUID a=UUID.randomUUID(),b=UUID.randomUUID(),recording=UUID.randomUUID();create(a,"첫 목록");create(b,"다른 목록");
  s.f.jdbc.update("INSERT INTO recording(id,user_id,song_id,revision,lifecycle_state) VALUES(?,?,?,1,'ACTIVE')",bytes(recording),bytes(s.f.registration.userId()),bytes(s.id));
  var first=json.readTree(add(a,s.id,1,UUID.randomUUID().toString()).getContentAsString());var other=json.readTree(add(b,s.id,1,UUID.randomUUID().toString()).getContentAsString());
  String item=first.get("item_id").asText(),foreign=other.get("item_id").asText();var songBefore=s.f.jdbc.queryForList("SELECT * FROM song");var recBefore=s.f.jdbc.queryForList("SELECT * FROM recording");
  assertThat(remove(a,foreign,2,UUID.randomUUID().toString()).getStatus()).isEqualTo(404);assertThat(remove(a,item,1,UUID.randomUUID().toString()).getStatus()).isEqualTo(409);assertThat(count("playlist_item")).isEqualTo(2);
  String op=UUID.randomUUID().toString();var response=remove(a,item,2,op);assertThat(response.getStatus()).isEqualTo(200);var wire=json.readTree(response.getContentAsString());assertThat(wire.get("items").size()).isZero();assertThat(wire.get("playlist").get("revision").asLong()).isEqualTo(3);
  assertThat(remove(a,item,2,op).getContentAsString()).isEqualTo(response.getContentAsString());assertThat(count("playlist_item")).isEqualTo(1);assertThat(count("deletion_ledger")).isEqualTo(1);
  assertThat(s.f.jdbc.queryForList("SELECT * FROM song")).usingRecursiveComparison().isEqualTo(songBefore);assertThat(s.f.jdbc.queryForList("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(recBefore);
  assertThat(s.f.jdbc.queryForObject("SELECT revision FROM playlist WHERE id=?",Long.class,bytes(b))).isEqualTo(2);
 }
 MockHttpServletResponse remove(UUID list,String item,long base,String op)throws Exception{return s.mvc.perform(delete("/v1/playlists/"+list+"/items/"+item).header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(Map.of("base_revision",base)))).andReturn().getResponse();}
 @Test void songTrashHidesOnlyItsLinksAndPublishesRetainedIdentity()throws Exception{
  s.postBody(s.f.key,s.body(""));UUID a=UUID.randomUUID(),b=UUID.randomUUID(),batch=UUID.randomUUID(),manual=UUID.randomUUID();create(a,"a");create(b,"b");
  s.f.jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,lifecycle_state,revision) VALUES(?,?,'MANUAL','직접 곡','가수','NORMAL','','ACTIVE',1)",bytes(manual),bytes(s.f.registration.userId()));
  multi(a,List.of(s.id,manual),1,UUID.randomUUID().toString());add(b,s.id,1,UUID.randomUUID().toString());
  var before=s.f.jdbc.queryForList("SELECT id,playlist_id,song_id,entry_key,position FROM playlist_item ORDER BY id");
  s.f.jdbc.execute("CREATE TABLE deletion_batch(id BINARY(16) PRIMARY KEY,user_id BINARY(16),mode VARCHAR(32))");s.f.jdbc.update("INSERT INTO deletion_batch VALUES(?,?,'SONG_ONLY')",bytes(batch),bytes(s.f.registration.userId()));
  s.f.jdbc.execute("CREATE TABLE deletion_item(batch_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16))");s.f.jdbc.update("INSERT INTO deletion_item VALUES(?,'SONG',?)",bytes(batch),bytes(s.id));var access=s.context.getBean(AccountAccess.class);var account=access.authenticate("Bearer "+s.f.tokens.accessToken(),s.f.registration.deviceId().toString());var revisions=s.context.getBean(com.ksh321.songrecord.api.revision.RevisionChanges.class);var changes=s.context.getBean(com.ksh321.songrecord.api.sync.AccountChanges.class);
  var events=new org.springframework.transaction.support.TransactionTemplate(new org.springframework.jdbc.datasource.DataSourceTransactionManager(s.f.jdbc.getDataSource())).execute(status->changes.write(account,()->{s.f.jdbc.update("UPDATE song SET lifecycle_state='TRASHED' WHERE id=?",bytes(s.id));var result=PlaylistService.hideTrashedSong(s.f.jdbc,revisions,account,s.id,batch,java.time.Clock.systemUTC());return new com.ksh321.songrecord.api.sync.AccountChanges.Batch<>(result,result);}).value());
  assertThat(events).hasSize(2);assertThat(s.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist_item WHERE hidden_by_batch_id=?",Long.class,bytes(batch))).isEqualTo(2);assertThat(s.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist_item WHERE song_id=? AND hidden_by_batch_id IS NULL",Long.class,bytes(manual))).isEqualTo(1);
  assertThat(s.f.jdbc.queryForList("SELECT id,playlist_id,song_id,entry_key,position FROM playlist_item ORDER BY id")).usingRecursiveComparison().isEqualTo(before);
  assertThat(s.context.getBean(PlaylistService.class).items("Bearer "+s.f.tokens.accessToken(),s.f.registration.deviceId().toString(),a.toString()).get("items")).asList().hasSize(1);
  assertThat(events).allSatisfy(e->assertThat(e.payload()).contains(batch.toString()));
 }
 @AfterEach void close()throws Exception{s.close();}
 MockHttpServletResponse write(String method,UUID id,String body,String op)throws Exception{
  var r=switch(method){case "POST"->post("/v1/playlists");case "PATCH"->patch("/v1/playlists/"+id);default->delete("/v1/playlists/"+id);};
  return s.mvc.perform(r.header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();
 }
 MockHttpServletResponse create(UUID id,String name)throws Exception{return write("POST",id,json.writeValueAsString(Map.of("id",id.toString(),"name",name)),UUID.randomUUID().toString());}
 long count(String table){return s.f.jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Long.class);}
 MockHttpServletResponse multi(UUID p,List<UUID> songs,long base,String op)throws Exception{return s.mvc.perform(post("/v1/playlists/"+p+"/items").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(Map.of("song_ids",songs.stream().map(UUID::toString).toList(),"base_revision",base)))).andReturn().getResponse();}
 @Test void multiSelectionIsAtomicIdempotentAndScopedToEachPlaylist()throws Exception{
  s.postBody(s.f.key,s.body(""));UUID a=UUID.randomUUID(),b=UUID.randomUUID(),manual=UUID.randomUUID();create(a,"첫 목록");create(b,"다른 목록");
  s.f.jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,lifecycle_state,revision) VALUES(?,?,'MANUAL','직접 곡','직접 가수','NORMAL','','ACTIVE',1)",bytes(manual),bytes(s.f.registration.userId()));
  assertThat(multi(a,List.of(s.id,UUID.randomUUID()),1,UUID.randomUUID().toString()).getStatus()).isEqualTo(404);assertThat(count("playlist_item")).isZero();
  assertThat(multi(a,List.of(s.id,s.id),1,UUID.randomUUID().toString()).getStatus()).isEqualTo(400);assertThat(count("playlist_item")).isZero();
  String op=UUID.randomUUID().toString();var first=multi(a,List.of(s.id,manual),1,op);assertThat(first.getStatus()).isEqualTo(201);
  var r=json.readTree(first.getContentAsString());assertThat(r.get("playlist").get("revision").asLong()).isEqualTo(2);assertThat(r.get("item_ids").size()).isEqualTo(2);assertThat(r.get("items").get(1).get("position").asLong()).isEqualTo(1);
  assertThat(multi(a,List.of(s.id,manual),1,op).getContentAsString()).isEqualTo(first.getContentAsString());
  long seq=s.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(s.f.registration.userId()));
  var duplicate=multi(a,List.of(s.id,manual),2,UUID.randomUUID().toString());assertThat(duplicate.getStatus()).isEqualTo(200);var d=json.readTree(duplicate.getContentAsString());assertThat(d.get("created").asBoolean()).isFalse();assertThat(d.get("item_ids")).isEqualTo(r.get("item_ids"));assertThat(d.get("playlist").get("revision").asLong()).isEqualTo(2);
  assertThat(s.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(s.f.registration.userId()))).isEqualTo(seq);
  assertThat(multi(a,List.of(s.id,manual),1,UUID.randomUUID().toString()).getStatus()).isEqualTo(409);assertThat(count("playlist_item")).isEqualTo(2);
  assertThat(multi(b,List.of(s.id,manual),1,UUID.randomUUID().toString()).getStatus()).isEqualTo(201);assertThat(count("playlist_item")).isEqualTo(4);
 }
 MockHttpServletResponse order(UUID p,List<String> ids,long base,String op)throws Exception{return s.mvc.perform(put("/v1/playlists/"+p+"/order").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(Map.of("ordered_item_ids",ids,"base_revision",base)))).andReturn().getResponse();}
 @Test void wholeOrderRejectsDuplicateMissingForeignAndStaleAtomically()throws Exception{
  s.postBody(s.f.key,s.body(""));UUID p=UUID.randomUUID(),other=UUID.randomUUID(),manual=UUID.randomUUID();create(p,"정렬");create(other,"다른 목록");
  s.f.jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,lifecycle_state,revision) VALUES(?,?,'MANUAL','직접 곡','가수','NORMAL','','ACTIVE',1)",bytes(manual),bytes(s.f.registration.userId()));
  var full=json.readTree(multi(p,List.of(s.id,manual),1,UUID.randomUUID().toString()).getContentAsString());String a=full.get("item_ids").get(0).asText(),b=full.get("item_ids").get(1).asText();
  var foreign=json.readTree(multi(other,List.of(s.id),1,UUID.randomUUID().toString()).getContentAsString()).get("item_ids").get(0).asText();
  var before=s.f.jdbc.queryForList("SELECT * FROM playlist_item WHERE playlist_id=? ORDER BY position",bytes(p));
  for(var ids:List.of(List.of(a,a),List.of(a),List.of(a,foreign)))assertThat(order(p,ids,2,UUID.randomUUID().toString()).getStatus()).isEqualTo(400);
  assertThat(s.f.jdbc.queryForList("SELECT * FROM playlist_item WHERE playlist_id=? ORDER BY position",bytes(p))).usingRecursiveComparison().isEqualTo(before);
  String op=UUID.randomUUID().toString();var success=order(p,List.of(b,a),2,op);assertThat(success.getStatus()).isEqualTo(200);var sorted=json.readTree(success.getContentAsString());assertThat(sorted.get("items").get(0).get("id").asText()).isEqualTo(b);assertThat(sorted.get("items").get(1).get("position").asLong()).isEqualTo(1);assertThat(sorted.get("playlist").get("revision").asLong()).isEqualTo(3);
  assertThat(order(p,List.of(b,a),2,op).getContentAsString()).isEqualTo(success.getContentAsString());assertThat(order(p,List.of(a,b),2,UUID.randomUUID().toString()).getStatus()).isEqualTo(409);
  assertThat(s.f.jdbc.queryForObject("SELECT revision FROM playlist WHERE id=?",Long.class,bytes(p))).isEqualTo(3);
  UUID empty=UUID.randomUUID();create(empty,"빈 목록");assertThat(order(empty,List.of(),1,UUID.randomUUID().toString()).getStatus()).isEqualTo(200);
 }
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
  s.postBody(s.f.key,s.body(""));var registered=add(p,s.id,3,UUID.randomUUID().toString());assertThat(registered.getStatus()).isEqualTo(200);
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
 MockHttpServletResponse link(UUID p,String item,UUID song,long base,String op)throws Exception{return s.mvc.perform(patch("/v1/playlists/"+p+"/items/"+item+"/song").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(Map.of("song_id",song.toString(),"base_revision",base)))).andReturn().getResponse();}
 @Test void creationLinksOnlySameOwnerNumberAndActiveParentWithoutChangingIdentityOrOrder()throws Exception{
  UUID a=UUID.randomUUID(),b=UUID.randomUUID(),deleted=UUID.randomUUID();create(a,"a");create(b,"b");create(deleted,"deleted");
  candidate(a,"valid",1,UUID.randomUUID().toString());candidate(a,"second",2,UUID.randomUUID().toString());candidate(b,"valid",1,UUID.randomUUID().toString());candidate(deleted,"valid",1,UUID.randomUUID().toString());
  write("DELETE",deleted,"{\"base_revision\":2}",UUID.randomUUID().toString());
  UUID foreignList=UUID.randomUUID();
  s.f.jdbc.update("INSERT INTO playlist(id,user_id,name,revision,created_at,updated_at) VALUES(?,?,'foreign',1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",bytes(foreignList),bytes(s.f.other.principal().userId()));
  s.f.jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,candidate_brand,candidate_number,candidate_snapshot,entry_key,position,created_at,updated_at) VALUES(?,?,?,NULL,'TJ','990001','{}','tj:990001',0,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",bytes(UUID.randomUUID()),bytes(s.f.other.principal().userId()),bytes(foreignList));
  var before=s.f.jdbc.queryForList("SELECT id,playlist_id,position,entry_key,candidate_snapshot FROM playlist_item ORDER BY id");
  long seq=s.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(s.f.registration.userId()));
  assertThat(s.postBody(s.f.key,s.body("")).getStatus()).isEqualTo(201);
  assertThat(s.f.jdbc.queryForList("SELECT id,playlist_id,position,entry_key,candidate_snapshot FROM playlist_item ORDER BY id")).usingRecursiveComparison().isEqualTo(before);
  assertThat(s.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist_item WHERE song_id=?",Long.class,bytes(s.id))).isEqualTo(2);
  assertThat(s.f.jdbc.queryForObject("SELECT revision FROM playlist WHERE id=?",Long.class,bytes(a))).isEqualTo(4);
  assertThat(s.f.jdbc.queryForObject("SELECT revision FROM playlist WHERE id=?",Long.class,bytes(b))).isEqualTo(3);
  assertThat(s.f.jdbc.queryForObject("SELECT COUNT(*) FROM change_log WHERE change_seq>? AND entity_type='PLAYLIST_ITEM'",Long.class,seq)).isEqualTo(2);
  assertThat(s.postBody(s.f.key,s.body("")).getStatus()).isEqualTo(201);
  assertThat(s.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(s.f.registration.userId()))).isEqualTo(seq+3);
 }
 @Test void exhaustedParentRevisionRollsBackNewSongAndAllCandidateLinks()throws Exception{
  UUID p=UUID.randomUUID();create(p,"rollback");candidate(p,"valid",1,UUID.randomUUID().toString());
  s.f.jdbc.update("UPDATE playlist SET revision=? WHERE id=?",Long.MAX_VALUE,bytes(p));
  var before=s.f.jdbc.queryForList("SELECT * FROM playlist_item");long receipts=count("mutation_receipt"),log=count("change_log");
  assertThat(s.postBody(s.f.key,s.body("")).getContentAsString()).contains("REVISION_LIMIT_REACHED");
  assertThat(count("song")).isZero();assertThat(count("song_source")).isZero();assertThat(count("mutation_receipt")).isEqualTo(receipts);assertThat(count("change_log")).isEqualTo(log);
  assertThat(s.f.jdbc.queryForList("SELECT * FROM playlist_item")).usingRecursiveComparison().isEqualTo(before);
 }
 @Test void explicitLinkRejectsManualOtherNumberForeignAndStaleThenReplaysWithoutReordering()throws Exception{
  UUID p=UUID.randomUUID(),manual=UUID.randomUUID(),other=UUID.randomUUID();create(p,"link");
  var added=json.readTree(candidate(p,"valid",1,UUID.randomUUID().toString()).getContentAsString());String item=added.get("item_id").asText();
  // Existing active Songs may precede a candidate imported from another device.
  for(UUID song:List.of(s.id,other,manual))s.f.jdbc.update("INSERT INTO song(id,user_id,source_type,tj_number,title,artist,version_code,lifecycle_state,revision) VALUES(?,?,?,?, 'title','artist','NORMAL','ACTIVE',1)",bytes(song),bytes(s.f.registration.userId()),song.equals(manual)?"MANUAL":"TJ",song.equals(manual)?null:song.equals(other)?"990002":"990001");
  var before=s.f.jdbc.queryForList("SELECT * FROM playlist_item");
  for(UUID song:List.of(manual,other))assertThat(link(p,item,song,2,UUID.randomUUID().toString()).getContentAsString()).contains("VALIDATION_FAILED");
  assertThat(link(p,item,UUID.randomUUID(),2,UUID.randomUUID().toString()).getStatus()).isEqualTo(404);
  assertThat(link(p,item,s.id,1,UUID.randomUUID().toString()).getContentAsString()).contains("REVISION_CONFLICT");
  assertThat(s.f.jdbc.queryForList("SELECT * FROM playlist_item")).usingRecursiveComparison().isEqualTo(before);
  String op=UUID.randomUUID().toString();var first=link(p,item,s.id,2,op);assertThat(first.getStatus()).isEqualTo(200);assertThat(first.getContentAsString()).contains("\"changed\":true");
  assertThat(link(p,item,s.id,2,op).getContentAsString()).isEqualTo(first.getContentAsString());
  var repeated=json.readTree(link(p,item,s.id,3,UUID.randomUUID().toString()).getContentAsString());assertThat(repeated.get("changed").asBoolean()).isFalse();assertThat(repeated.get("playlist").get("revision").asLong()).isEqualTo(3);assertThat(repeated.get("items").get(0).get("position").asLong()).isZero();assertThat(repeated.get("item_id").asText()).isEqualTo(item);
 }
}
