package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.songs.SongDeletionPreview;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

class SongDeletionPreviewTests {
    final SongCreationTests s=new SongCreationTests();
    final tools.jackson.databind.json.JsonMapper json=new tools.jackson.databind.json.JsonMapper();
    UUID a=UUID.randomUUID(),b=UUID.randomUUID();
    @BeforeEach void open()throws Exception{
        s.setup();assertThat(s.postBody(s.f.key,s.body("")).getStatus()).isEqualTo(201);
        s.f.jdbc.execute("CREATE TABLE recording_asset(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),cloud_state VARCHAR(16),cloud_revision BIGINT,generation BIGINT,verified_size BIGINT)");
        s.f.jdbc.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,revision BIGINT,current_recording_id BINARY(16),pending_recording_id BINARY(16))");
        recording(a,"ACTIVE");recording(b,"ACTIVE");
        s.f.jdbc.update("INSERT INTO recording_asset VALUES(?,?,'STORED',1,1,1234)",bytes(a),bytes(owner()));
        s.f.jdbc.update("INSERT INTO recording_asset VALUES(?,?,'UPLOADING',1,1,9000)",bytes(b),bytes(owner()));
        s.f.jdbc.update("INSERT INTO pin_slot VALUES(?,1,1,?,?)",bytes(owner()),bytes(a),bytes(b));
    }
    @AfterEach void close()throws Exception{s.close();}
    UUID owner(){return s.f.registration.userId();}
    void recording(UUID id,String state){s.f.jdbc.update("INSERT INTO recording(id,user_id,song_id,revision,link_revision,metadata_state,lifecycle_state) VALUES(?,?,?,1,1,'SAVED',?)",bytes(id),bytes(owner()),bytes(s.id),state);}
    MockHttpServletResponse getPreview(UUID song)throws Exception{return s.mvc.perform(get("/v1/songs/"+song+"/delete-preview").header("Authorization","Bearer "+s.f.tokens.accessToken()).header("X-Device-Id",s.f.registration.deviceId())).andReturn().getResponse();}
    String token()throws Exception{return json.readTree(getPreview(s.id).getContentAsString()).get("preview_version").asText();}
    void check(String token){var account=s.f.access.authenticate("Bearer "+s.f.tokens.accessToken(),s.f.registration.deviceId().toString());new TransactionTemplate(s.f.manager).execute(status->{s.context.getBean(SongDeletionPreview.class).requireUnchanged(account,s.id,token);return null;});}
    void changed(String token){assertThatThrownBy(()->check(token)).isInstanceOf(ApiException.class).extracting("code").isEqualTo("DELETE_PREVIEW_CHANGED");}
    @Test void countsOnlyActiveLinkedServerKnownScopeAndHasNoSideEffects()throws Exception{
        UUID trashed=UUID.randomUUID(),orphan=UUID.randomUUID();recording(trashed,"TRASHED");recording(orphan,"ACTIVE");s.f.jdbc.update("UPDATE recording SET song_id=NULL WHERE id=?",bytes(orphan));
        var song=s.f.jdbc.queryForList("SELECT * FROM song");var recordings=s.f.jdbc.queryForList("SELECT * FROM recording");long changes=s.f.jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Long.class);
        var response=getPreview(s.id);assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");var wire=json.readTree(response.getContentAsString());
        assertThat(wire.get("recording_count").asInt()).isEqualTo(2);assertThat(wire.get("server_bytes").asLong()).isEqualTo(1234);assertThat(wire.get("pinned_count").asInt()).isEqualTo(2);assertThat(wire.get("scope").asText()).isEqualTo("SERVER_SYNCED_ONLY");
        assertThat(wire.get("preview_version").asText()).matches("[0-9a-f]{64}");check(token());assertThat(token()).isEqualTo(token());
        assertThat(s.f.jdbc.queryForList("SELECT * FROM song")).usingRecursiveComparison().isEqualTo(song);assertThat(s.f.jdbc.queryForList("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(recordings);assertThat(s.f.jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Long.class)).isEqualTo(changes);
        assertThat(response.getContentAsString()).doesNotContain(a.toString(),b.toString(),owner().toString(),"object_key");
    }
    @Test void replacementWithEqualCountsAndBytesStillInvalidatesConfirmation()throws Exception{
        String old=token();UUID replacement=UUID.randomUUID();recording(replacement,"ACTIVE");s.f.jdbc.update("UPDATE recording SET song_id=NULL WHERE id=?",bytes(b));changed(old);
    }
    @Test void filePinRevisionAndSongChangesEachRequireNewConfirmation()throws Exception{
        String old=token();s.f.jdbc.update("UPDATE recording_asset SET cloud_state='STORED',cloud_revision=2 WHERE recording_id=?",bytes(b));changed(old);
        old=token();s.f.jdbc.update("UPDATE pin_slot SET pending_recording_id=NULL,revision=2");changed(old);
        old=token();s.f.jdbc.update("UPDATE recording SET link_revision=2 WHERE id=?",bytes(a));changed(old);
        old=token();s.f.jdbc.update("UPDATE song SET revision=revision+1 WHERE id=?",bytes(s.id));changed(old);
        check(token());
    }
    @Test void absentForeignOrTrashedSongCannotBePreviewedAndAuthPrecedesInput()throws Exception{
        assertThat(getPreview(UUID.randomUUID()).getStatus()).isEqualTo(404);
        s.f.jdbc.update("UPDATE song SET user_id=? WHERE id=?",bytes(UUID.randomUUID()),bytes(s.id));assertThat(getPreview(s.id).getStatus()).isEqualTo(404);
        s.f.jdbc.update("UPDATE song SET user_id=?,lifecycle_state='TRASHED' WHERE id=?",bytes(owner()),bytes(s.id));assertThat(getPreview(s.id).getStatus()).isEqualTo(404);
        assertThat(s.mvc.perform(get("/v1/songs/not-an-id/delete-preview")).andReturn().getResponse().getStatus()).isEqualTo(401);
    }
    @Test void invalidTokenAndComparisonOutsideMutationCannotAuthorizeDeletion()throws Exception{
        changed(null);changed("invalid");var account=s.f.access.authenticate("Bearer "+s.f.tokens.accessToken(),s.f.registration.deviceId().toString());
        assertThatThrownBy(()->s.context.getBean(SongDeletionPreview.class).requireUnchanged(account,s.id,"invalid")).isInstanceOf(IllegalStateException.class);
    }
}
