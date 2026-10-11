package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

class RecordingTrashTests {
    final SongTrashTests f=new SongTrashTests();
    @BeforeEach void open()throws Exception{f.open();}
    @AfterEach void close()throws Exception{f.close();}
    org.springframework.mock.web.MockHttpServletResponse trash(UUID id,String op,long revision,boolean confirm)throws Exception{
        return f.s.mvc.perform(post("/v1/recordings/"+id+"/trash").header("Authorization","Bearer "+f.f.tokens.accessToken()).header("X-Device-Id",f.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(f.json.writeValueAsString(Map.of("base_revision",revision,"pin_release_confirmed",confirm)))).andReturn().getResponse();
    }
    @Test void confirmationIsRequiredAndDeletionRetainsBytesAndSong()throws Exception{
        var db=f.f.jdbc;var asset=db.queryForMap("SELECT * FROM recording_asset");
        assertThat(trash(f.recording,UUID.randomUUID().toString(),1,false).getContentAsString()).contains("PIN_RELEASE_CONFIRMATION_REQUIRED");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isZero();
        String op=UUID.randomUUID().toString();var response=trash(f.recording,op,1,true);assertThat(response.getStatus()).isEqualTo(200);
        var result=f.json.readTree(response.getContentAsString());assertThat(java.time.Instant.parse(result.get("purge_after").asText())).isEqualTo(java.time.Instant.parse(result.get("deleted_at").asText()).plusSeconds(7*86400));
        assertThat(result.get("recording").get("title_snapshot").asText()).isEqualTo("당시 곡");assertThat(result.get("recording").get("tier").asText()).isEqualTo("D");
        assertThat(db.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("ACTIVE");assertThat(db.queryForObject("SELECT representative_recording_id FROM song",byte[].class)).isNull();
        assertThat(db.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("TRASHED");assertThat(db.queryForObject("SELECT current_recording_id FROM pin_slot",byte[].class)).isNull();
        assertThat(db.queryForObject("SELECT hidden_by_batch_id FROM playlist_item",byte[].class)).isNull();
        for(String key:List.of("CLOUD_STATE","OBJECT_KEY","GENERATION","VERIFIED_SIZE","SHA256"))assertThat(db.queryForMap("SELECT * FROM recording_asset").get(key)).isEqualTo(asset.get(key));
        assertThat(db.queryForObject("SELECT previous_song_id FROM deletion_item",byte[].class)).isEqualTo(bytes(f.s.id));
        assertThat(db.queryForObject("SELECT detached_link_revision FROM deletion_item",Long.class)).isEqualTo(2);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE type='POLICY_RECALCULATE'",Integer.class)).isGreaterThan(0);
        assertThat(trash(f.recording,op,1,true).getContentAsString()).isEqualTo(response.getContentAsString());assertThat(db.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isEqualTo(1);
    }
    @Test void pendingDeletionPreservesUnrelatedCurrentPin()throws Exception{
        var db=f.f.jdbc;UUID current=UUID.randomUUID();var body=f.r.setup.base();body.put("id",current.toString());assertThat(f.r.setup.create(body).getStatus()).isEqualTo(201);
        db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(current));
        db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','unrelated-file',?,1234,?,CURRENT_TIMESTAMP)",bytes(current),bytes(f.owner()),bytes(UUID.randomUUID()),"b".repeat(64));
        UUID operation=UUID.randomUUID();db.update("UPDATE pin_slot SET current_recording_id=?,pending_recording_id=?,operation_id=?,requested_at=CURRENT_TIMESTAMP",bytes(current),bytes(f.recording),bytes(operation));
        assertThat(trash(f.recording,UUID.randomUUID().toString(),1,true).getStatus()).isEqualTo(200);
        assertThat(db.queryForObject("SELECT current_recording_id FROM pin_slot",byte[].class)).isEqualTo(bytes(current));assertThat(db.queryForObject("SELECT pending_recording_id FROM pin_slot",byte[].class)).isNull();assertThat(db.queryForObject("SELECT operation_id FROM pin_slot",byte[].class)).isEqualTo(bytes(operation));
        assertThat(db.queryForObject("SELECT lifecycle_state FROM recording WHERE id=?",String.class,bytes(current))).isEqualTo("ACTIVE");
    }
    @Test void staleRevisionUnknownOwnerAndRepeatedNewOperationCannotExtendExpiry()throws Exception{
        assertThat(trash(f.recording,UUID.randomUUID().toString(),2,true).getStatus()).isEqualTo(409);
        assertThat(trash(UUID.randomUUID(),UUID.randomUUID().toString(),1,true).getStatus()).isEqualTo(404);
        assertThat(trash(f.recording,UUID.randomUUID().toString(),1,true).getStatus()).isEqualTo(200);var date=f.f.jdbc.queryForObject("SELECT deleted_at FROM recording",java.sql.Timestamp.class);
        assertThat(trash(f.recording,UUID.randomUUID().toString(),2,true).getContentAsString()).contains("RECORDING_NOT_ACTIVE");assertThat(f.f.jdbc.queryForObject("SELECT deleted_at FROM recording",java.sql.Timestamp.class)).isEqualTo(date);
        assertThat(f.s.mvc.perform(post("/v1/recordings/"+f.recording+"/trash").contentType("application/json").content("{}")).andReturn().getResponse().getStatus()).isEqualTo(401);
    }
}
