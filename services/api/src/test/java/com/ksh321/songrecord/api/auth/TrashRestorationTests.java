package com.ksh321.songrecord.api.auth;
import java.util.*;
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
class TrashRestorationTests {
    final SongTrashTests f=new SongTrashTests();
    @BeforeEach void open()throws Exception{f.open();}
    @AfterEach void close()throws Exception{f.close();}
    String batch(String mode)throws Exception{return f.json.readTree(f.trash(f.s.id,UUID.randomUUID().toString(),f.preview(),mode).getContentAsString()).get("batch_id").asText();}
    org.springframework.mock.web.MockHttpServletResponse restore(String batch,String op,long revision,List<String> ids)throws Exception{
        var body=new LinkedHashMap<String,Object>();body.put("base_revision",revision);if(ids!=null)body.put("item_ids",ids);
        return f.s.mvc.perform(post("/v1/trash/"+batch+"/restore").header("Authorization","Bearer "+f.f.tokens.accessToken()).header("X-Device-Id",f.f.registration.deviceId()).header("Idempotency-Key",op).contentType("application/json").content(f.json.writeValueAsString(body))).andReturn().getResponse();
    }
    @Test void songOnlyRestoresOriginalLinkWithoutAutomaticallyReassigningRepresentative()throws Exception{
        String b=batch("SONG_ONLY"),op=UUID.randomUUID().toString();var dates=f.f.jdbc.queryForMap("SELECT deleted_at,purge_after FROM deletion_batch");
        var result=restore(b,op,1,null);assertThat(result.getStatus()).isEqualTo(200);assertThat(f.json.readTree(result.getContentAsString()).get("restored").size()).isEqualTo(3);
        assertThat(f.f.jdbc.queryForObject("SELECT song_id FROM recording",byte[].class)).isEqualTo(bytes(f.s.id));assertThat(f.f.jdbc.queryForObject("SELECT link_revision FROM recording",Long.class)).isEqualTo(3);
        assertThat(f.f.jdbc.queryForObject("SELECT representative_recording_id FROM song",byte[].class)).isNull();assertThat(f.f.jdbc.queryForObject("SELECT current_recording_id FROM pin_slot",byte[].class)).isEqualTo(bytes(f.recording));
        assertThat(f.f.jdbc.queryForMap("SELECT deleted_at,purge_after FROM deletion_batch")).usingRecursiveComparison().isEqualTo(dates);
        assertThat(restore(b,op,1,null).getContentAsString()).isEqualTo(result.getContentAsString());assertThat(restore(b,UUID.randomUUID().toString(),1,null).getContentAsString()).contains("REVISION_CONFLICT");
        var listed=f.s.mvc.perform(get("/v1/trash").header("Authorization","Bearer "+f.f.tokens.accessToken()).header("X-Device-Id",f.f.registration.deviceId())).andReturn().getResponse();
        assertThat(f.json.readTree(listed.getContentAsString()).get("items").size()).isZero();assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch",Integer.class)).isEqualTo(1);
    }
    @Test void selectedSongKeepsDeletedRecordingsAndLinksNewCandidateWithoutRevivingHiddenDuplicate()throws Exception{
        f.f.jdbc.update("UPDATE playlist_item SET entry_key='tj:990001'");
        String b=batch("SONG_AND_RECORDINGS");
        var recordingBefore=f.f.jdbc.queryForMap("SELECT * FROM recording");
        UUID candidate=UUID.randomUUID(),otherParent=UUID.randomUUID(),otherCandidate=UUID.randomUUID();
        f.f.jdbc.update("INSERT INTO playlist(id,user_id,name,created_at) VALUES(?,?,'new candidate list',CURRENT_TIMESTAMP)",bytes(otherParent),bytes(f.owner()));
        for(var pair:List.of(Map.entry(f.parent,candidate),Map.entry(otherParent,otherCandidate)))
            f.f.jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,candidate_brand,candidate_number,candidate_snapshot,entry_key,position,created_at,updated_at) VALUES(?,?,?,'TJ','990001',?,'tj:990001',19,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",bytes(pair.getValue()),bytes(f.owner()),bytes(pair.getKey()),"{\"title\":\"candidate\",\"artist\":\"artist\"}");
        String op=UUID.randomUUID().toString();var response=restore(b,op,1,List.of(f.s.id.toString()));
        assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getContentAsString()).contains("DUPLICATE_ACTIVE");
        assertThat(f.f.jdbc.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(recordingBefore);
        assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("ACTIVE");
        assertThat(f.f.jdbc.queryForObject("SELECT hidden_by_batch_id FROM playlist_item WHERE id=?",byte[].class,bytes(f.item))).isEqualTo(bytes(UUID.fromString(b)));
        for(UUID id:List.of(candidate,otherCandidate)){
            assertThat(f.f.jdbc.queryForObject("SELECT song_id FROM playlist_item WHERE id=?",byte[].class,bytes(id))).isEqualTo(bytes(f.s.id));
            assertThat(f.f.jdbc.queryForObject("SELECT position FROM playlist_item WHERE id=?",Long.class,bytes(id))).isEqualTo(19);
        }
        assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist_item WHERE hidden_by_batch_id IS NULL",Integer.class)).isEqualTo(2);
        var before=f.f.jdbc.queryForList("SELECT * FROM playlist_item ORDER BY id");
        assertThat(restore(b,op,1,List.of(f.s.id.toString())).getContentAsString()).isEqualTo(response.getContentAsString());
        assertThat(f.f.jdbc.queryForList("SELECT * FROM playlist_item ORDER BY id")).usingRecursiveComparison().isEqualTo(before);
        // Database uniqueness still prevents a second visible item and old-row resurrection.
        assertThatThrownBy(()->f.f.jdbc.update("UPDATE playlist_item SET hidden_by_batch_id=NULL WHERE id=?",bytes(f.item))).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
    }
    @Test void laterRelinkIsNotOverwrittenBySongRestoration()throws Exception{
        String b=batch("SONG_ONLY");UUID original=f.s.id;f.s.id=UUID.randomUUID();assertThat(f.s.postBody(UUID.randomUUID().toString(),f.s.body("").replace("valid","second")).getStatus()).isEqualTo(201);UUID later=f.s.id;
        f.f.jdbc.update("UPDATE recording SET song_id=?,link_revision=link_revision+1,revision=revision+1 WHERE id=?",bytes(later),bytes(f.recording));
        var result=restore(b,UUID.randomUUID().toString(),1,List.of(original.toString()));assertThat(result.getStatus()).isEqualTo(200);assertThat(result.getContentAsString()).contains("LINK_CHANGED");assertThat(f.f.jdbc.queryForObject("SELECT song_id FROM recording",byte[].class)).isEqualTo(bytes(later));assertThat(f.f.jdbc.queryForObject("SELECT link_revision FROM recording",Long.class)).isEqualTo(3);
    }
    @Test void purgedParentAllowsOnlySelectedRecordingToRestoreUnlinkedWithoutPin()throws Exception{
        String b=batch("SONG_AND_RECORDINGS");var file=f.f.jdbc.queryForMap("SELECT object_key,generation,verified_size,sha256 FROM recording_asset");f.f.jdbc.update("UPDATE song SET lifecycle_state='PURGED' WHERE id=?",bytes(f.s.id));
        var result=restore(b,UUID.randomUUID().toString(),1,List.of(f.recording.toString()));assertThat(result.getStatus()).isEqualTo(200);assertThat(result.getContentAsString()).contains("\"pin_reselection_required\":true");
        assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM song",String.class)).isEqualTo("PURGED");assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("ACTIVE");assertThat(f.f.jdbc.queryForObject("SELECT song_id FROM recording",byte[].class)).isNull();assertThat(f.f.jdbc.queryForObject("SELECT current_recording_id FROM pin_slot",byte[].class)).isNull();assertThat(f.f.jdbc.queryForMap("SELECT object_key,generation,verified_size,sha256 FROM recording_asset")).usingRecursiveComparison().isEqualTo(file);
    }
    @Test void foreignSelectionAndExpiredBatchCannotModifyAnything()throws Exception{
        String b=batch("SONG_AND_RECORDINGS");assertThat(restore(b,UUID.randomUUID().toString(),1,List.of(UUID.randomUUID().toString())).getStatus()).isEqualTo(400);assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch_work",Integer.class)).isZero();
        f.f.jdbc.update("UPDATE deletion_batch SET deleted_at=?,purge_after=?",java.sql.Timestamp.valueOf("2026-01-01 00:00:00"),java.sql.Timestamp.valueOf("2026-01-08 00:00:00"));
        assertThat(restore(b,UUID.randomUUID().toString(),1,null).getContentAsString()).contains("TRASH_EXPIRED");assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM recording",String.class)).isEqualTo("TRASHED");
    }
    @Test void listingRequiresAuthenticationAndOwnCursor()throws Exception{
        batch("SONG_ONLY");var request=get("/v1/trash").header("Authorization","Bearer "+f.f.tokens.accessToken()).header("X-Device-Id",f.f.registration.deviceId());var result=f.s.mvc.perform(request).andReturn().getResponse();assertThat(result.getStatus()).isEqualTo(200);assertThat(result.getHeader("Cache-Control")).isEqualTo("no-store");assertThat(f.json.readTree(result.getContentAsString()).get("items").size()).isEqualTo(1);
        assertThat(f.s.mvc.perform(get("/v1/trash")).andReturn().getResponse().getStatus()).isEqualTo(401);assertThat(f.s.mvc.perform(request.param("cursor",UUID.randomUUID().toString())).andReturn().getResponse().getStatus()).isEqualTo(400);
    }
}
