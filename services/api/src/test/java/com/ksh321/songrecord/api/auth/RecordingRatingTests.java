package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class RecordingRatingTests {
    final RecordingEditingTests setup=new RecordingEditingTests();
    @BeforeEach void open()throws Exception{setup.open();}
    @AfterEach void close()throws Exception{setup.close();}
    MockHttpServletResponse rate(String body)throws Exception{return setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id+"/tier").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body)).andReturn().getResponse();}
    void saved()throws Exception{
        assertThat(setup.setup.create(setup.setup.base()).getStatus()).isEqualTo(201);
        var file=Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        assertThat(setup.edit(Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","title","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file)).getStatus()).isEqualTo(200);
    }
    @Test void mysqlSharedAtomicityReplayIndependenceAndConcurrency(){
        var context=setup.setup.setup.context;RecordingRatingDatabaseChecks.verify(setup.f.jdbc,context.getBean(RecordingDrafts.class),context.getBean(RecordingEditing.class),context.getBean(RecordingRating.class),"Bearer "+setup.f.tokens.accessToken(),setup.f.registration.deviceId().toString(),setup.f.registration.userId());
    }
    @Test void allRatingsAndClearAllowedWithoutLinkedSongOrCloud()throws Exception{
        saved();long revision=2;
        for(String tier:List.of("S","A","B","C","D","null")){
            var response=rate("{\"base_revision\":"+revision+",\"tier\":"+(tier.equals("null")?"null":"\""+tier+"\"")+"}");
            assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
            var node=setup.json.readTree(response.getContentAsString());assertThat(node.get("revision").asLong()).isEqualTo(++revision);
            if(tier.equals("null"))assertThat(node.get("tier").isNull()).isTrue();else assertThat(node.get("tier").asText()).isEqualTo(tier);
        }
        assertThat(setup.setup.setup.count("job")).isZero();assertThat(setup.setup.setup.count("recording_asset")).isZero();
    }
    @Test void draftInactiveAndMalformedRequestsNeverChangeRating()throws Exception{
        setup.setup.create(setup.setup.base());
        assertThat(rate("{\"base_revision\":1,\"tier\":\"A\"}").getContentAsString()).contains("RECORDING_NOT_SAVED");
        assertThat(rate("{\"base_revision\":1,\"tier\":null}").getStatus()).isEqualTo(409);
        for(String body:List.of("{}","{\"base_revision\":1}","{\"base_revision\":0,\"tier\":null}","{\"base_revision\":1.5,\"tier\":null}","{\"base_revision\":1,\"tier\":\"E\"}","{\"base_revision\":1,\"tier\":\"a\"}","{\"base_revision\":1,\"tier\":1}","{\"base_revision\":1,\"tier\":\"A\",\"note\":\"x\"}","{\"base_revision\":1,\"tier\":null,\"tier\":\"A\"}"))assertThat(rate(body).getStatus()).as(body).isEqualTo(400);
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){setup.f.jdbc.update("UPDATE recording SET lifecycle_state=?",state);assertThat(rate("{\"base_revision\":1,\"tier\":\"A\"}").getContentAsString()).contains("RECORDING_NOT_ACTIVE");}
        assertThat(setup.f.jdbc.queryForObject("SELECT revision FROM recording",Long.class)).isEqualTo(1);assertThat(setup.setup.setup.count("job")).isZero();
    }
    @Test void authenticationAndSameDeviceOtherAccountCannotRate()throws Exception{
        saved();String body="{\"base_revision\":2,\"tier\":\"S\"}";
        assertThat(setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id+"/tier").contentType("application/json").content(body)).andReturn().getResponse().getStatus()).isEqualTo(401);
        var p=setup.f.other.principal();var tokens=setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
        assertThat(setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id+"/tier").header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body)).andReturn().getResponse().getStatus()).isEqualTo(404);
    }
    @Test void newTierIsVisibleToFiltersAndExpiresCursor()throws Exception{
        saved();UUID target=setup.setup.id;setup.setup.id=UUID.randomUUID();saved();setup.setup.id=target;
        String cursor=setup.json.readTree(setup.listing.list("sort","TIER","limit","1").getContentAsString()).get("next_cursor").asText();
        assertThat(rate("{\"base_revision\":2,\"tier\":\"S\"}").getStatus()).isEqualTo(200);
        assertThat(setup.listing.list("sort","TIER","limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
        var page=setup.json.readTree(setup.listing.list("tier","S").getContentAsString());assertThat(page.get("count").asInt()).isEqualTo(1);assertThat(page.get("items").get(0).get("id").asText()).isEqualTo(target.toString());
        var conflict=rate("{\"base_revision\":2,\"tier\":\"D\"}");assertThat(conflict.getStatus()).isEqualTo(409);assertThat(conflict.getContentAsString()).contains("REVISION_CONFLICT","current_revision","tag_ids");
        assertThat(setup.f.jdbc.queryForObject("SELECT tier FROM recording WHERE id=?",String.class,bytes(target))).isEqualTo("S");
    }
}
