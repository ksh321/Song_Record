package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

class SongRepresentativeTests {
    final SongCreationTests setup=new SongCreationTests();final JsonMapper json=new JsonMapper();UUID song,recording;String path;
    @BeforeEach void open()throws Exception{
        setup.setup();new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(setup.f.keeper);song=setup.id;path="/v1/songs/"+song+"/representative";
        assertThat(setup.postBody(UUID.randomUUID().toString(),setup.body("")).getStatus()).isEqualTo(201);
        recording=seed(setup.f.registration.userId(),song,"SAVED","ACTIVE");
    }
    @AfterEach void close()throws Exception{setup.close();}
    UUID seed(UUID owner,UUID linked,String metadata,String lifecycle){
        UUID id=UUID.randomUUID();setup.f.jdbc.update("INSERT INTO recording(id,user_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,tier,note,metadata_state,lifecycle_state,recorded_at) VALUES(?,?,?,'past','artist','LIVE','FEMALE',-2,'D','keep',?,?,CURRENT_TIMESTAMP)",bytes(id),bytes(owner),linked==null?null:bytes(linked),metadata,lifecycle);return id;
    }
    String body(long revision,UUID id){return "{\"base_revision\":"+revision+",\"recording_id\":"+(id==null?"null":"\""+id+"\"")+"}";}
    MockHttpServletResponse putBody(String op,String body)throws Exception{return setup.mvc.perform(put(path).header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();}
    MockHttpServletResponse select(long revision,UUID id)throws Exception{return putBody(UUID.randomUUID().toString(),body(revision,id));}
    long revision(){return setup.f.jdbc.queryForObject("SELECT revision FROM song WHERE id=?",Long.class,bytes(song));}
    @Test void selectsReplacesClearsAndPreservesRecordingAndSearchMetadata()throws Exception{
        var db=setup.f.jdbc;var before=db.queryForMap("SELECT * FROM recording");var keys=db.queryForMap("SELECT * FROM song_query_key");
        var response=select(1,recording);assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(json.readTree(response.getContentAsString()).get("representative_recording_id").asText()).isEqualTo(recording.toString());
        assertThat(db.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(before);
        UUID second=seed(setup.f.registration.userId(),song,"SAVED","ACTIVE");assertThat(select(2,second).getStatus()).isEqualTo(200);
        var listed=setup.mvc.perform(get("/v1/songs").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId())).andReturn().getResponse();
        assertThat(json.readTree(listed.getContentAsString()).get("items").get(0).get("representative_recording_id").asText()).isEqualTo(second.toString());
        var clear=select(3,null);assertThat(clear.getStatus()).isEqualTo(200);assertThat(json.readTree(clear.getContentAsString()).get("representative_recording_id").isNull()).isTrue();
        assertThat(db.queryForObject("SELECT representative_recording_id FROM song",byte[].class)).isNull();assertThat(revision()).isEqualTo(4);
        assertThat(db.queryForMap("SELECT * FROM song_query_key")).usingRecursiveComparison().isEqualTo(keys);
        assertThat(db.queryForObject("SELECT payload FROM change_log WHERE change_seq=4",String.class)).contains("\"representative_recording_id\":null");
        // Repeated desired state with a NEW operation still has one revision; receipt replay does not.
        assertThat(select(4,null).getStatus()).isEqualTo(200);assertThat(revision()).isEqualTo(5);
    }
    @Test void replayDoesNotReselectAfterClearAndConflictReturnsCurrentWireSong()throws Exception{
        String op=UUID.randomUUID().toString(),body=body(1,recording);var first=putBody(op,body);assertThat(first.getStatus()).isEqualTo(200);
        assertThat(select(2,null).getStatus()).isEqualTo(200);
        assertThat(putBody(op,body).getContentAsString()).isEqualTo(first.getContentAsString());assertThat(revision()).isEqualTo(3);
        assertThat(putBody(op,body(1,null)).getContentAsString()).contains("IDEMPOTENCY_CONFLICT");
        var stale=select(1,recording);assertThat(stale.getStatus()).isEqualTo(409);var error=json.readTree(stale.getContentAsString()).get("error");
        assertThat(error.get("code").asText()).isEqualTo("REVISION_CONFLICT");assertThat(error.get("details").get("current_revision").asInt()).isEqualTo(3);
        var current=error.get("details").get("current");assertThat(current.get("representative_recording_id").isNull()).isTrue();assertThat(current.has("tier")).isTrue();assertThat(current.has("song_tier")).isFalse();
        assertThat(setup.count("change_log")).isEqualTo(3);
    }
    @Test void rejectsForeignMissingUnlinkedOtherSongDraftAndInactiveRecordings()throws Exception{
        UUID foreign=seed(setup.f.other.principal().userId(),song,"SAVED","ACTIVE");
        for(UUID id:List.of(foreign,UUID.randomUUID())){var r=select(1,id);assertThat(r.getStatus()).isEqualTo(404);assertThat(r.getContentAsString()).contains("RESOURCE_NOT_FOUND");}
        var owner=setup.f.registration.userId();
        for(UUID id:List.of(seed(owner,null,"SAVED","ACTIVE"),seed(owner,UUID.randomUUID(),"SAVED","ACTIVE"),seed(owner,song,"DRAFT","ACTIVE"),seed(owner,song,"SAVED","TRASHED"),seed(owner,song,"SAVED","PURGE_PENDING"),seed(owner,song,"SAVED","PURGED"))){
            var r=select(1,id);assertThat(r.getStatus()).isEqualTo(409);assertThat(r.getContentAsString()).contains("REPRESENTATIVE_NOT_ELIGIBLE");
        }
        assertThat(revision()).isEqualTo(1);assertThat(setup.count("mutation_receipt")).isEqualTo(1);assertThat(setup.count("change_log")).isEqualTo(1);
    }
    @Test void enforcesAuthenticationOwnerAndSongLifecycleEvenOnClear()throws Exception{
        assertThat(setup.mvc.perform(put(path).contentType("application/json").content(body(1,null))).andReturn().getResponse().getStatus()).isEqualTo(401);
        var principal=setup.f.other.principal();var token=setup.f.sessions.issue(new AccountRegistrationService.Registration(principal.userId(),principal.deviceId(),false));
        assertThat(setup.mvc.perform(put(path).header("Authorization","Bearer "+token.accessToken()).header("X-Device-Id",principal.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body(1,null))).andReturn().getResponse().getStatus()).isEqualTo(404);
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){setup.f.jdbc.update("UPDATE song SET lifecycle_state=?",state);assertThat(select(1,null).getStatus()).isEqualTo(409);}
        assertThat(revision()).isEqualTo(1);
    }
    @Test void strictBodyValidationAndGeneralPatchCannotBypassEligibility()throws Exception{
        for(String body:List.of("{}","[]","{\"base_revision\":1}","{\"recording_id\":null}","{\"base_revision\":0,\"recording_id\":null}","{\"base_revision\":1.5,\"recording_id\":null}","{\"base_revision\":9223372036854775808,\"recording_id\":null}","{\"base_revision\":1,\"recording_id\":true}","{\"base_revision\":1,\"recording_id\":\"1-1-1-1-1\"}","{\"base_revision\":1,\"recording_id\":null,\"note\":\"x\"}"))assertThat(putBody(UUID.randomUUID().toString(),body).getStatus()).as(body).isEqualTo(400);
        assertThat(setup.mvc.perform(patch("/v1/songs/"+song).header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content("{\"base_revision\":1,\"representative_recording_id\":\""+recording+"\"}")).andReturn().getResponse().getStatus()).isEqualTo(400);
        assertThat(revision()).isEqualTo(1);
    }
    @Test void failedChangeLogRollsBackPointerRevisionReceiptAndSequenceThenSameKeyRetries()throws Exception{
        String op=UUID.randomUUID().toString(),body=body(1,recording);var before=setup.f.jdbc.queryForMap("SELECT * FROM song");
        setup.f.jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT reject_selection CHECK(revision=1)");
        assertThat(putBody(op,body).getStatus()).isEqualTo(500);
        assertThat(setup.f.jdbc.queryForMap("SELECT * FROM song")).usingRecursiveComparison().isEqualTo(before);
        assertThat(setup.count("mutation_receipt")).isEqualTo(1);assertThat(setup.count("change_log")).isEqualTo(1);
        assertThat(setup.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(setup.f.registration.userId()))).isEqualTo(1);
        setup.f.jdbc.execute("ALTER TABLE change_log DROP CONSTRAINT reject_selection");assertThat(putBody(op,body).getStatus()).isEqualTo(200);
    }
}
