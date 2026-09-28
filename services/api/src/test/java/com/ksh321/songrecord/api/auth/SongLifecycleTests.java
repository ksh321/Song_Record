package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.songs.*;
import java.util.*;
import org.junit.jupiter.api.*;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class SongLifecycleTests {
    final SongCreationTests setup=new SongCreationTests();
    @BeforeEach void open()throws Exception{setup.setup();setup.f.jdbc.execute("ALTER TABLE deletion_ledger ADD id BINARY(16)");}
    @AfterEach void close()throws Exception{setup.close();}
    @Test void reservationsAndTombstonesSurviveStateChangesAndReceiptExpiry(){
        SongLifecycleDatabaseChecks.verify(setup.f.jdbc,setup.context.getBean(SongCreation.class),"Bearer "+setup.f.tokens.accessToken(),setup.f.registration.deviceId().toString(),setup.f.registration.userId(),"valid");
    }
    @Test void httpConflictIdentifiesOwnedRestoreTargetWithoutOverwritingIt()throws Exception{
        assertThat(setup.postBody(UUID.randomUUID().toString(),setup.body("")).getStatus()).isEqualTo(201);UUID original=setup.id;
        setup.f.jdbc.update("UPDATE song SET lifecycle_state='TRASHED',revision=7");setup.id=UUID.randomUUID();
        var response=setup.postBody(UUID.randomUUID().toString(),setup.body(",\"title\":\"overwrite\""));assertThat(response.getStatus()).isEqualTo(409);
        var error=new JsonMapper().readTree(response.getContentAsString()).get("error");assertThat(error.get("code").asText()).isEqualTo("SONG_RESTORE_REQUIRED");
        assertThat(error.get("details").get("canonical_song_id").asText()).isEqualTo(original.toString());assertThat(error.get("details").get("current_revision").asInt()).isEqualTo(7);
        assertThat(setup.f.jdbc.queryForObject("SELECT title FROM song",String.class)).isEqualTo("원본 곡");
    }
}
