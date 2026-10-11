package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

class SongTrashTests {
    final RecordingListingTests r=new RecordingListingTests();final JsonMapper json=new JsonMapper();
    SongCreationTests s;IdempotencyTests f;UUID recording,parent,item;
    @BeforeEach void open()throws Exception{
        r.open();s=r.setup.setup;f=s.f;
        new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(f.keeper);
        f.jdbc.execute("ALTER TABLE song_cloud_selection ADD selection_revision BIGINT DEFAULT 1");f.jdbc.execute("ALTER TABLE song_cloud_selection ADD updated_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
        f.jdbc.execute("ALTER TABLE pin_slot ADD revision BIGINT DEFAULT 1");
        f.jdbc.execute("CREATE TABLE deletion_batch(id BINARY(16) PRIMARY KEY,user_id BINARY(16),op_id BINARY(16),mode VARCHAR(32),deleted_at TIMESTAMP(3),purge_after TIMESTAMP(3),preview_version VARCHAR(128),UNIQUE(user_id,op_id))");
        f.jdbc.execute("CREATE TABLE deletion_item(batch_id BINARY(16),user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),previous_song_id BINARY(16),previous_list_id BINARY(16),detached_link_revision BIGINT,original_deleted_at TIMESTAMP(3),PRIMARY KEY(batch_id,entity_type,entity_id))");
        f.jdbc.execute("CREATE TABLE cloud_hold(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16),reason VARCHAR(32))");
        f.jdbc.execute("CREATE TABLE recording_upload(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16),state VARCHAR(32),policy_revision BIGINT,expires_at TIMESTAMP(3),updated_at TIMESTAMP(3),expected_size BIGINT,active_slot INT,reservation_released_at TIMESTAMP(3),error_code VARCHAR(64),pin_operation_id BINARY(16))");
        f.jdbc.execute("ALTER TABLE pin_slot ADD operation_id BINARY(16)");f.jdbc.execute("ALTER TABLE pin_slot ADD requested_at TIMESTAMP(3)");f.jdbc.execute("ALTER TABLE pin_slot ADD updated_at TIMESTAMP(3)");
        f.jdbc.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,used_bytes BIGINT DEFAULT 0,reserved_bytes BIGINT DEFAULT 0,revision BIGINT DEFAULT 1,updated_at TIMESTAMP(3))");
        f.jdbc.update("INSERT INTO global_storage_usage(id) VALUES(1)");
        assertThat(s.postBody(UUID.randomUUID().toString(),s.body("")).getStatus()).isEqualTo(201);
        recording=r.setup.id;var body=r.setup.base();body.put("song_id",s.id.toString());body.put("title_snapshot","당시 곡");body.put("artist_snapshot","당시 가수");body.put("key_mode","FEMALE");body.put("key_shift",-2);body.put("version_code","LIVE");body.put("note","메모 보존");assertThat(r.setup.create(body).getStatus()).isEqualTo(201);
        f.jdbc.update("UPDATE recording SET metadata_state='SAVED',tier='D' WHERE id=?",bytes(recording));
        f.jdbc.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','synthetic-file',?,1234,?,CURRENT_TIMESTAMP)",bytes(recording),bytes(owner()),bytes(UUID.randomUUID()),"a".repeat(64));
        f.jdbc.update("INSERT INTO pin_slot(user_id,slot_no,current_recording_id) VALUES(?,1,?)",bytes(owner()),bytes(recording));
        f.jdbc.update("INSERT INTO song_cloud_selection(song_id,user_id,representative_id,latest_id,lowest_tier_id) VALUES(?,?,?,?,?)",bytes(s.id),bytes(owner()),bytes(recording),bytes(recording),bytes(recording));
        f.jdbc.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(recording),bytes(s.id));
        parent=UUID.randomUUID();item=UUID.randomUUID();f.jdbc.update("INSERT INTO playlist(id,user_id,name,created_at) VALUES(?,?,'list',CURRENT_TIMESTAMP)",bytes(parent),bytes(owner()));
        f.jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,entry_key,position,created_at,updated_at) VALUES(?,?,?,?,?,7,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",bytes(item),bytes(owner()),bytes(parent),bytes(s.id),"TJ:990001");
    }
    @AfterEach void close()throws Exception{r.close();}
    UUID owner(){return f.registration.userId();}
    String preview()throws Exception{var response=s.mvc.perform(get("/v1/songs/"+s.id+"/delete-preview").header("Authorization","Bearer "+f.tokens.accessToken()).header("X-Device-Id",f.registration.deviceId())).andReturn().getResponse();assertThat(response.getStatus()).isEqualTo(200);return json.readTree(response.getContentAsString()).get("preview_version").asText();}
    MockHttpServletResponse trash(UUID song,String op,String token,String mode)throws Exception{return s.mvc.perform(post("/v1/songs/"+song+"/trash").header("Authorization","Bearer "+f.tokens.accessToken()).header("X-Device-Id",f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(json.writeValueAsString(Map.of("mode",mode,"preview_version",token)))).andReturn().getResponse();}
    @Test void songOnlyPreservesMetadataFilePinsAndCreatesExactRestorationRelations()throws Exception{
        var metadata=new LinkedHashMap<>(f.jdbc.queryForMap("SELECT * FROM recording WHERE id=?",bytes(recording)));for(String key:List.of("SONG_ID","REVISION","LINK_REVISION","UPDATED_AT"))metadata.remove(key);
        var pins=f.jdbc.queryForList("SELECT * FROM pin_slot");var asset=f.jdbc.queryForMap("SELECT object_key,generation,verified_size,sha256,cloud_state FROM recording_asset");
        String token=preview(),op=UUID.randomUUID().toString();var response=trash(s.id,op,token,"SONG_ONLY");assertThat(response.getStatus()).isEqualTo(200);var reply=json.readTree(response.getContentAsString());assertThat(reply.get("recordings").get(0).get("song_id").isNull()).isTrue();assertThat(reply.get("song").get("lifecycle_state").asText()).isEqualTo("TRASHED");
        var after=new LinkedHashMap<>(f.jdbc.queryForMap("SELECT * FROM recording WHERE id=?",bytes(recording)));for(String key:List.of("SONG_ID","REVISION","LINK_REVISION","UPDATED_AT"))after.remove(key);assertThat(after).usingRecursiveComparison().isEqualTo(metadata);
        assertThat(f.jdbc.queryForList("SELECT * FROM pin_slot")).usingRecursiveComparison().isEqualTo(pins);assertThat(f.jdbc.queryForMap("SELECT object_key,generation,verified_size,sha256,cloud_state FROM recording_asset")).usingRecursiveComparison().isEqualTo(asset);
        assertThat(f.jdbc.queryForObject("SELECT song_id FROM recording",byte[].class)).isNull();assertThat(f.jdbc.queryForObject("SELECT link_revision FROM recording",Long.class)).isEqualTo(2);assertThat(f.jdbc.queryForObject("SELECT representative_recording_id FROM song",byte[].class)).isNull();
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_item",Integer.class)).isEqualTo(3);assertThat(f.jdbc.queryForObject("SELECT detached_link_revision FROM deletion_item WHERE entity_type='RECORDING'",Long.class)).isEqualTo(2);
        assertThat(f.jdbc.queryForObject("SELECT previous_song_id FROM deletion_item WHERE entity_type='PLAYLIST_ITEM'",byte[].class)).isEqualTo(bytes(s.id));
        assertThat(f.jdbc.queryForObject("SELECT hidden_by_batch_id FROM playlist_item",byte[].class)).isEqualTo(bytes(UUID.fromString(reply.get("batch_id").asText())));assertThat(f.jdbc.queryForObject("SELECT position FROM playlist_item",Long.class)).isEqualTo(7);
        assertThat(f.jdbc.queryForObject("SELECT reason FROM cloud_hold",String.class)).isEqualTo("ORPHAN_KEEP");assertThat(f.jdbc.queryForObject("SELECT latest_id FROM song_cloud_selection",byte[].class)).isNull();
        assertThat(trash(s.id,op,token,"SONG_ONLY").getContentAsString()).isEqualTo(response.getContentAsString());assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isEqualTo(1);
    }
    @Test void changedPreviewAndInvalidModeCannotMutateAnything()throws Exception{
        String token=preview();f.jdbc.update("UPDATE recording SET link_revision=link_revision+1 WHERE id=?",bytes(recording));var failed=trash(s.id,UUID.randomUUID().toString(),token,"SONG_ONLY");assertThat(failed.getStatus()).isEqualTo(409);assertThat(failed.getContentAsString()).contains("DELETE_PREVIEW_CHANGED");
        assertThat(trash(s.id,UUID.randomUUID().toString(),preview(),"unknown").getStatus()).isEqualTo(400);assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isZero();assertThat(f.jdbc.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("ACTIVE");
    }
    @Test void approvedUploadKeepsExpiryAndMovesOnlyItsCurrentPolicy()throws Exception{
        f.jdbc.update("UPDATE recording_asset SET cloud_state='NONE',object_key=NULL,generation=NULL,verified_size=NULL,sha256=NULL,stored_at=NULL");
        UUID attempt=UUID.randomUUID();var expiry=java.sql.Timestamp.from(java.time.Instant.now().plusSeconds(3600).truncatedTo(java.time.temporal.ChronoUnit.MILLIS));
        f.jdbc.update("INSERT INTO recording_upload(id,user_id,recording_id,state,policy_revision,expires_at) VALUES(?,?,?,'UPLOADING',1,?)",bytes(attempt),bytes(owner()),bytes(recording),expiry);
        assertThat(trash(s.id,UUID.randomUUID().toString(),preview(),"SONG_ONLY").getStatus()).isEqualTo(200);
        assertThat(f.jdbc.queryForObject("SELECT policy_revision FROM recording_upload",Long.class)).isEqualTo(2);
        assertThat(f.jdbc.queryForObject("SELECT expires_at FROM recording_upload",java.sql.Timestamp.class)).isEqualTo(expiry);
        assertThat(f.jdbc.queryForObject("SELECT state FROM recording_upload",String.class)).isEqualTo("UPLOADING");
        assertThat(f.jdbc.queryForObject("SELECT reason FROM cloud_hold",String.class)).isEqualTo("ORPHAN_KEEP");
    }
    @Test void togetherTrashesOnlyActiveTargetsAndPreservesFilesAndOlderExpiry()throws Exception{
        UUID old=UUID.randomUUID();var body=r.setup.base();body.put("id",old.toString());body.put("song_id",s.id.toString());assertThat(r.setup.create(body).getStatus()).isEqualTo(201);
        var prior=java.sql.Timestamp.valueOf("2026-10-01 00:00:00");f.jdbc.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=? WHERE id=?",prior,bytes(old));
        var asset=f.jdbc.queryForMap("SELECT object_key,generation,verified_size,sha256,cloud_state FROM recording_asset");
        var response=trash(s.id,UUID.randomUUID().toString(),preview(),"SONG_AND_RECORDINGS");assertThat(response.getStatus()).isEqualTo(200);var result=json.readTree(response.getContentAsString());
        assertThat(result.get("recordings").size()).isEqualTo(1);assertThat(result.get("recordings").get(0).get("lifecycle_state").asText()).isEqualTo("TRASHED");
        assertThat(result.get("recordings").get(0).get("deleted_at").asText()).isEqualTo(result.get("deleted_at").asText());
        assertThat(f.jdbc.queryForObject("SELECT deleted_at FROM recording WHERE id=?",java.sql.Timestamp.class,bytes(old))).isEqualTo(prior);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_item WHERE entity_id=?",Integer.class,bytes(old))).isZero();
        assertThat(f.jdbc.queryForObject("SELECT current_recording_id FROM pin_slot",byte[].class)).isNull();
        assertThat(f.jdbc.queryForMap("SELECT object_key,generation,verified_size,sha256,cloud_state FROM recording_asset")).usingRecursiveComparison().isEqualTo(asset);
    }
    @Test void togetherCancelsUploadAndReleasesOnlyReservationOnce()throws Exception{
        f.jdbc.update("UPDATE recording_asset SET cloud_state='NONE',object_key=NULL,generation=NULL,verified_size=NULL,sha256=NULL,stored_at=NULL");
        UUID attempt=UUID.randomUUID();f.jdbc.update("INSERT INTO recording_upload(id,user_id,recording_id,state,policy_revision,expires_at,expected_size,active_slot) VALUES(?,?,?,'UPLOADING',1,?,3,0)",bytes(attempt),bytes(owner()),bytes(recording),java.sql.Timestamp.from(java.time.Instant.now().plusSeconds(3600)));
        f.jdbc.update("UPDATE storage_usage SET reserved_bytes=3 WHERE user_id=?",bytes(owner()));f.jdbc.update("UPDATE global_storage_usage SET reserved_bytes=3");
        String op=UUID.randomUUID().toString(),version=preview();var response=trash(s.id,op,version,"SONG_AND_RECORDINGS");assertThat(response.getStatus()).isEqualTo(200);
        assertThat(f.jdbc.queryForObject("SELECT state FROM recording_upload",String.class)).isEqualTo("CANCELLED");
        assertThat(f.jdbc.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner()))).isZero();assertThat(f.jdbc.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner()))).isZero();
        assertThat(f.jdbc.queryForObject("SELECT reserved_bytes FROM global_storage_usage",Long.class)).isZero();assertThat(trash(s.id,op,version,"SONG_AND_RECORDINGS").getContentAsString()).isEqualTo(response.getContentAsString());
    }
    @Test void pinRevisionLimitRollsBackTheEntireTrashBatch()throws Exception{
        f.jdbc.update("UPDATE pin_slot SET revision=?",Long.MAX_VALUE);
        var response=trash(s.id,UUID.randomUUID().toString(),preview(),"SONG_AND_RECORDINGS");assertThat(response.getStatus()).isEqualTo(409);assertThat(response.getContentAsString()).contains("PIN_REVISION_LIMIT_REACHED");
        assertThat(f.jdbc.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("ACTIVE");assertThat(f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("ACTIVE");
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isZero();assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_item",Integer.class)).isZero();
        assertThat(f.jdbc.queryForObject("SELECT hidden_by_batch_id FROM playlist_item",byte[].class)).isNull();
    }
    @Test void staleApprovalIsNotRevivedAsOrphanProtection()throws Exception{
        f.jdbc.update("UPDATE recording_asset SET cloud_state='NONE',object_key=NULL,generation=NULL,verified_size=NULL,sha256=NULL,stored_at=NULL,cloud_revision=2");
        f.jdbc.update("INSERT INTO recording_upload(id,user_id,recording_id,state,policy_revision,expires_at) VALUES(?,?,?,'UPLOADING',1,?)",bytes(UUID.randomUUID()),bytes(owner()),bytes(recording),java.sql.Timestamp.from(java.time.Instant.now().plusSeconds(3600)));
        assertThat(trash(s.id,UUID.randomUUID().toString(),preview(),"SONG_ONLY").getStatus()).isEqualTo(200);
        assertThat(f.jdbc.queryForObject("SELECT policy_revision FROM recording_upload",Long.class)).isEqualTo(1);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM cloud_hold",Integer.class)).isZero();
    }
    @Test void fileDeletionAlreadyInProgressAndForeignSongAreRejected()throws Exception{
        f.jdbc.update("UPDATE recording_asset SET cloud_state='DELETING'");var blocked=trash(s.id,UUID.randomUUID().toString(),preview(),"SONG_ONLY");assertThat(blocked.getStatus()).isEqualTo(409);assertThat(blocked.getContentAsString()).contains("FILE_CLEANUP_IN_PROGRESS");
        assertThat(trash(UUID.randomUUID(),UUID.randomUUID().toString(),preview(),"SONG_ONLY").getStatus()).isEqualTo(404);assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isZero();
    }
}
