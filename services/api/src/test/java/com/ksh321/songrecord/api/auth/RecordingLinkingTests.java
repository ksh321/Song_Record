package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class RecordingLinkingTests {
    final RecordingEditingTests setup=new RecordingEditingTests();
    @BeforeEach void open()throws Exception{setup.open();setup.f.jdbc.execute("ALTER TABLE song_cloud_selection ADD selection_revision BIGINT DEFAULT 1");setup.f.jdbc.execute("ALTER TABLE song_cloud_selection ADD updated_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");}
    @AfterEach void close()throws Exception{setup.close();}
    UUID song(UUID owner,String state){UUID id=UUID.randomUUID();setup.f.jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,lifecycle_state) VALUES(?,?,'MANUAL','different title','different artist','MR','different note',?)",bytes(id),bytes(owner),state);return id;}
    MockHttpServletResponse link(String body)throws Exception{return setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id+"/song").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body)).andReturn().getResponse();}
    @Test void sharedMySqlScenarioPreservesSnapshotsAndRollsBackEveryParticipant(){var c=setup.setup.setup.context;RecordingLinkingDatabaseChecks.verify(setup.f.jdbc,c.getBean(RecordingDrafts.class),c.getBean(RecordingEditing.class),c.getBean(RecordingLinking.class),"Bearer "+setup.f.tokens.accessToken(),setup.f.registration.deviceId().toString(),setup.f.registration.userId(),new com.ksh321.songrecord.api.jobs.JobQueue(setup.f.jdbc,setup.f.access,setup.f.manager,setup.f.clock,java.time.Duration.ofMinutes(2),3));}
    @Test void incompleteDraftCanLinkWithoutCopyingSongValuesAndCursorExpires()throws Exception{
        setup.setup.create(setup.setup.base());UUID target=setup.setup.id;setup.setup.id=UUID.randomUUID();setup.setup.create(setup.setup.base());setup.setup.id=target;
        String cursor=setup.json.readTree(setup.listing.list("limit","1").getContentAsString()).get("next_cursor").asText();UUID song=song(setup.f.registration.userId(),"ACTIVE");
        var response=link(setup.json.writeValueAsString(Map.of("base_revision",1,"song_id",song.toString())));assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        var node=setup.json.readTree(response.getContentAsString());assertThat(node.get("title_snapshot").isNull()).isTrue();assertThat(node.get("artist_snapshot").isNull()).isTrue();assertThat(node.get("version_code").asText()).isEqualTo("NORMAL");assertThat(node.get("note").asText()).isEmpty();assertThat(node.get("metadata_state").asText()).isEqualTo("DRAFT");assertThat(node.get("link_revision").asLong()).isEqualTo(2);
        assertThat(setup.listing.list("limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
        assertThat(setup.json.readTree(setup.listing.list("song_id",song.toString()).getContentAsString()).get("count").asInt()).isEqualTo(1);
        assertThat(link("{\"base_revision\":1,\"song_id\":null}").getContentAsString()).contains("REVISION_CONFLICT","link_revision");
    }
    @Test void ownershipStateValidationAndOverflowDoNotMutate()throws Exception{
        setup.setup.create(setup.setup.base());UUID other=song(setup.f.other.principal().userId(),"ACTIVE");
        assertThat(link(setup.json.writeValueAsString(Map.of("base_revision",1,"song_id",other.toString()))).getStatus()).isEqualTo(404);
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){UUID target=song(setup.f.registration.userId(),state);assertThat(link(setup.json.writeValueAsString(Map.of("base_revision",1,"song_id",target.toString()))).getContentAsString()).contains("SONG_NOT_ACTIVE");}
        for(String body:List.of("{}","{\"base_revision\":1}","{\"base_revision\":0,\"song_id\":null}","{\"base_revision\":1,\"song_id\":1}","{\"base_revision\":1,\"song_id\":\"bad\"}","{\"base_revision\":1,\"song_id\":null,\"title_snapshot\":\"x\"}"))assertThat(link(body).getStatus()).isEqualTo(400);
        UUID target=song(setup.f.registration.userId(),"ACTIVE");setup.f.jdbc.update("UPDATE recording SET link_revision=?",Long.MAX_VALUE);assertThat(link(setup.json.writeValueAsString(Map.of("base_revision",1,"song_id",target.toString()))).getContentAsString()).contains("LINK_REVISION_LIMIT_REACHED");
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){setup.f.jdbc.update("UPDATE recording SET lifecycle_state=?",state);assertThat(link("{\"base_revision\":1,\"song_id\":null}").getContentAsString()).contains("RECORDING_NOT_ACTIVE");}
        assertThat(setup.f.jdbc.queryForObject("SELECT revision FROM recording",Long.class)).isEqualTo(1);assertThat(setup.setup.setup.count("job")).isZero();
    }
    @Test void authAndOtherOwnerRecordingReturn401And404()throws Exception{
        setup.setup.create(setup.setup.base());String body="{\"base_revision\":1,\"song_id\":null}";
        assertThat(setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id+"/song").contentType("application/json").content(body)).andReturn().getResponse().getStatus()).isEqualTo(401);
        var p=setup.f.other.principal();var tokens=setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));
        assertThat(setup.setup.setup.mvc.perform(patch("/v1/recordings/"+setup.setup.id+"/song").header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",p.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body)).andReturn().getResponse().getStatus()).isEqualTo(404);
    }
}
