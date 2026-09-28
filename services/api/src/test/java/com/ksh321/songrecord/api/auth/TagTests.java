package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.classifications.*;
import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class TagTests {
    final RecordingEditingTests setup=new RecordingEditingTests();
    @BeforeEach void open()throws Exception{
        setup.open();
        // H2 counts UTF-16 units in VARCHAR; MySQL utf8mb4 counts code points. API enforces 50.
        setup.f.jdbc.execute("ALTER TABLE tag ALTER COLUMN name VARCHAR(100)");
        setup.f.jdbc.execute("ALTER TABLE recording_tag ALTER COLUMN name_snapshot VARCHAR(100)");
        setup.f.jdbc.execute("ALTER TABLE tag ADD created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
        setup.f.jdbc.execute("ALTER TABLE tag ADD active_name_key VARBINARY(800) GENERATED ALWAYS AS (CASE WHEN archived_at IS NULL THEN normalized_name_key ELSE NULL END)");
        setup.f.jdbc.execute("CREATE UNIQUE INDEX uq_test_tag_name ON tag(user_id,active_name_key)");
    }
    @AfterEach void close()throws Exception{setup.close();}
    MockHttpServletResponse create(UUID id,String name)throws Exception{return setup.setup.setup.mvc.perform(post("/v1/tags").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(setup.json.writeValueAsString(Map.of("id",id.toString(),"name",name)))).andReturn().getResponse();}
    MockHttpServletResponse rename(UUID id,long revision,String name)throws Exception{return setup.setup.setup.mvc.perform(patch("/v1/tags/"+id).header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(setup.json.writeValueAsString(Map.of("base_revision",revision,"name",name)))).andReturn().getResponse();}
    MockHttpServletResponse list(String... params)throws Exception{var r=get("/v1/tags").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId());for(int i=0;i<params.length;i+=2)r.param(params[i],params[i+1]);return setup.setup.setup.mvc.perform(r).andReturn().getResponse();}
    @Test void mysqlSharedHistoryUniquenessArchiveRollbackAndRace(){var c=setup.setup.setup.context;TagDatabaseChecks.verify(setup.f.jdbc,c.getBean(TagService.class),c.getBean(RecordingDrafts.class),c.getBean(RecordingEditing.class),"Bearer "+setup.f.tokens.accessToken(),setup.f.registration.deviceId().toString(),setup.f.registration.userId());}
    @Test void normalizationUnicodeLengthAndRenameCollision()throws Exception{
        UUID id=UUID.randomUUID();assertThat(create(id,"\u3000École\u3000").getStatus()).isEqualTo(201);assertThat(create(UUID.randomUUID(),"E\u0301cole").getStatus()).isEqualTo(409);
        assertThat(create(UUID.randomUUID(),"   ").getStatus()).isEqualTo(400);assertThat(create(UUID.randomUUID(),"😀".repeat(50)).getStatus()).isEqualTo(201);assertThat(create(UUID.randomUUID(),"😀".repeat(51)).getStatus()).isEqualTo(400);
        UUID other=UUID.randomUUID();assertThat(create(other,"Hello").getStatus()).isEqualTo(201);assertThat(rename(id,1,"hello").getContentAsString()).contains("TAG_NAME_IN_USE");
        assertThat(rename(id,1,"renamed").getStatus()).isEqualTo(200);assertThat(rename(id,1,"stale").getContentAsString()).contains("REVISION_CONFLICT","current_revision");
    }
    @Test void pagingCursorScopeAndInvalidParameters()throws Exception{
        var ids=new ArrayList<UUID>();for(String name:List.of("b","A","c")){UUID id=UUID.randomUUID();ids.add(id);create(id,name);}
        var first=list("limit","1");assertThat(first.getStatus()).isEqualTo(200);assertThat(first.getHeader("Cache-Control")).isEqualTo("no-store");var p=setup.json.readTree(first.getContentAsString());assertThat(p.get("count").asInt()).isEqualTo(3);assertThat(p.get("items").get(0).get("name").asText()).isEqualTo("A");String cursor=p.get("next_cursor").asText();
        assertThat(list("limit","1","cursor",cursor).getStatus()).isEqualTo(200);assertThat(list("limit","1","cursor",cursor,"state","ALL").getStatus()).isEqualTo(400);
        rename(ids.getFirst(),1,"z");assertThat(list("limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
        for(String[] params:List.of(new String[]{"state","BAD"},new String[]{"limit","0"},new String[]{"limit","101"},new String[]{"unknown","x"},new String[]{"state","ACTIVE","state","ALL"}))assertThat(list(params).getStatus()).isEqualTo(400);
    }
    @Test void ownershipAuthenticationAndTombstoneAreEnforced()throws Exception{
        UUID id=UUID.randomUUID();create(id,"private");assertThat(setup.setup.setup.mvc.perform(get("/v1/tags")).andReturn().getResponse().getStatus()).isEqualTo(401);
        var p=setup.f.other.principal();var tokens=setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
        var otherList=setup.setup.setup.mvc.perform(get("/v1/tags").header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId())).andReturn().getResponse();assertThat(setup.json.readTree(otherList.getContentAsString()).get("count").asInt()).isZero();
        var request=patch("/v1/tags/"+id).header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content("{\"base_revision\":1,\"name\":\"other\"}");assertThat(setup.setup.setup.mvc.perform(request).andReturn().getResponse().getStatus()).isEqualTo(404);
        UUID purged=UUID.randomUUID();setup.f.jdbc.update("INSERT INTO deletion_ledger(user_id,entity_type,entity_id,revision) VALUES(?,'TAG',?,2)",bytes(setup.f.registration.userId()),bytes(purged));assertThat(create(purged,"purged").getContentAsString()).contains("RESOURCE_PURGED");
    }
    @Test void archiveEndpointRejectsMissingRevisionAndKeepsExistingTimestamp()throws Exception{
        UUID id=UUID.randomUUID();create(id,"name");
        for(String body:List.of("{}","{\"base_revision\":0}","{\"base_revision\":1,\"name\":\"x\"}"))assertThat(archive(id,body).getStatus()).isEqualTo(400);
        var first=archive(id,"{\"base_revision\":1}");assertThat(first.getStatus()).isEqualTo(200);String time=setup.json.readTree(first.getContentAsString()).get("archived_at").asText();
        var second=archive(id,"{\"base_revision\":2}");assertThat(second.getStatus()).isEqualTo(200);assertThat(setup.json.readTree(second.getContentAsString()).get("archived_at").asText()).isEqualTo(time);
        assertThat(create(id,"retry").getContentAsString()).contains("TAG_ARCHIVED");assertThat(setup.json.readTree(list("state","ARCHIVED").getContentAsString()).get("count").asInt()).isEqualTo(1);
    }
    MockHttpServletResponse archive(UUID id,String body)throws Exception{return setup.setup.setup.mvc.perform(post("/v1/tags/"+id+"/archive").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body)).andReturn().getResponse();}
}
