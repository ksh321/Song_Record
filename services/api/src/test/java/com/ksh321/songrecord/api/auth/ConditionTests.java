package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.classifications.*;
import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class ConditionTests {
    final RecordingEditingTests setup=new RecordingEditingTests();
    @BeforeEach void open()throws Exception{setup.open();}
    @AfterEach void close()throws Exception{setup.close();}
    String auth(){return "Bearer "+setup.f.tokens.accessToken();}
    String device(){return setup.f.registration.deviceId().toString();}
    void seedLegacy()throws Exception{
        setup.setup.create(setup.setup.base());
        UUID custom=UUID.randomUUID();
        setup.f.jdbc.update("INSERT INTO condition_definition(id,user_id,code,name,normalized_name_key) VALUES(?,?,?,?,?)",bytes(custom),bytes(setup.f.registration.userId()),custom.toString(),"이전 정의",new byte[]{1});
        setup.f.jdbc.update("UPDATE recording SET condition_code=?,condition_name_snapshot=? WHERE id=?",custom.toString(),"당시 이름",bytes(setup.setup.id));
        setup.f.jdbc.update("UPDATE condition_definition SET name='바뀐 기본값',archived_at=CURRENT_TIMESTAMP WHERE code='GOOD'");
    }
    @Test void fixedCatalogIgnoresLegacyNamesAndArchive()throws Exception{
        seedLegacy();
        var r=setup.setup.setup.mvc.perform(get("/v1/conditions").header("Authorization",auth()).header("X-Device-Id",device())).andReturn().getResponse();
        assertThat(r.getStatus()).isEqualTo(200);assertThat(r.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(setup.json.readTree(r.getContentAsString())).isEqualTo(setup.json.readTree(setup.json.writeValueAsString(new ConditionService.Catalog(ConditionCatalog.ITEMS))));
        assertThat(setup.setup.setup.mvc.perform(get("/v1/conditions").header("Authorization",auth()).header("X-Device-Id",device()).param("state","ALL")).andReturn().getResponse().getStatus()).isEqualTo(400);
        assertThat(setup.setup.setup.mvc.perform(get("/v1/conditions")).andReturn().getResponse().getStatus()).isEqualTo(401);
    }
    @Test void headSupportsAdvertisedReadMethod()throws Exception{
        var r=setup.setup.setup.mvc.perform(head("/v1/conditions").header("Authorization",auth()).header("X-Device-Id",device())).andReturn().getResponse();
        assertThat(r.getStatus()).isEqualTo(200);assertThat(r.getContentAsByteArray()).isEmpty();
    }
    @Test void writesAre405EvenWithoutJsonBodyAndNeverCreateReceipts()throws Exception{
        long receipts=setup.setup.setup.count("mutation_receipt");
        for(var request:List.of(post("/v1/conditions"),patch("/v1/conditions/invalid"),post("/v1/conditions/invalid/archive"))){
            var r=setup.setup.setup.mvc.perform(request.header("Authorization",auth()).header("X-Device-Id",device())).andReturn().getResponse();
            assertThat(r.getStatus()).isEqualTo(405);assertThat(r.getContentAsString()).contains("CONDITION_CATALOG_READ_ONLY");
            assertThat(r.getHeader("Cache-Control")).isEqualTo("no-store");
        }
        assertThat(setup.setup.setup.count("mutation_receipt")).isEqualTo(receipts);
        assertThat(setup.setup.setup.mvc.perform(post("/v1/conditions")).andReturn().getResponse().getStatus()).isEqualTo(401);
    }
    @Test void historySelectionReplayRollbackAndConcurrentRejection()throws Exception{
        seedLegacy();var c=setup.setup.setup.context;
        ConditionDatabaseChecks.verify(setup.f.jdbc,c.getBean(ConditionService.class),c.getBean(RecordingDrafts.class),c.getBean(RecordingEditing.class),auth(),device(),setup.f.registration.userId(),setup.setup.id);
    }
    @Test void legacyReadFilterAndOwnershipRemainWhileNewUuidSelectionIsRejected()throws Exception{
        seedLegacy();String old=setup.f.jdbc.queryForObject("SELECT condition_code FROM recording WHERE id=?",String.class,bytes(setup.setup.id));
        var r=setup.listing.list("condition_code",old);assertThat(setup.json.readTree(r.getContentAsString()).get("count").asInt()).isEqualTo(1);
        assertThat(setup.edit(Map.of("base_revision",1,"condition_code",old)).getStatus()).isEqualTo(400);
        var p=setup.f.other.principal();var tokens=setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
        var denied=setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id).header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content("{\"base_revision\":1,\"condition_code\":\"GOOD\"}")).andReturn().getResponse();
        assertThat(denied.getStatus()).isEqualTo(404);
        assertThat(setup.f.jdbc.queryForObject("SELECT condition_code FROM recording WHERE id=?",String.class,bytes(setup.setup.id))).isEqualTo(old);
    }
}
