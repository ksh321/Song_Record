package com.ksh321.songrecord.api.recordings;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Same relink scenario on H2 and fully migrated MySQL, including composite FK enforcement. */
public final class RecordingLinkingDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private RecordingLinkingDatabaseChecks(){}
    public static void verify(JdbcTemplate db,RecordingDrafts drafts,RecordingEditing editing,RecordingLinking linking,String auth,String device,UUID owner){
        // Old ID deliberately sorts after the destination. Locks must not follow navigation order.
        UUID old=UUID.fromString("eeeeeeee-0000-4000-8000-000000000001"),next=UUID.fromString("11111111-0000-4000-8000-000000000002"),id=UUID.randomUUID();
        for(UUID song:List.of(old,next))db.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,song_tier,lifecycle_state) VALUES(?,?,'MANUAL','song','artist','NORMAL','','S','ACTIVE')",bytes(song),bytes(owner));
        drafts.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",id.toString(),"metadata_state","DRAFT","song_id",old.toString(),"recorded_at","2026-09-28T07:00:00Z","timezone_id","Asia/Seoul","timezone_offset_minutes",540)));
        var file=Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        editing.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","capture title","artist_snapshot","capture artist","version_code","LIVE","key_mode","MALE","key_shift",-2,"note","capture note","file",file)));
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(id),bytes(old));
        db.update("INSERT INTO song_cloud_selection(song_id,user_id,representative_id,latest_id,lowest_tier_id) VALUES(?,?,?,?,?)",bytes(old),bytes(owner),bytes(id),bytes(id),bytes(id));
        db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at) VALUES(?,?,'STORED','test/object',?,100,?,CURRENT_TIMESTAMP)",bytes(id),bytes(owner),bytes(UUID.randomUUID()),"a".repeat(64));
        var assetBefore=db.queryForMap("SELECT * FROM recording_asset WHERE recording_id=?",bytes(id));
        var fileBefore=db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?",bytes(id));
        var before=db.queryForMap("SELECT * FROM recording WHERE id=?",bytes(id));var oldBefore=db.queryForMap("SELECT * FROM song WHERE id=?",bytes(old));
        var nextBefore=db.queryForMap("SELECT * FROM song WHERE id=?",bytes(next));var selectionBefore=db.queryForMap("SELECT * FROM song_cloud_selection WHERE song_id=?",bytes(old));
        String op=UUID.randomUUID().toString(),body=JSON.writeValueAsString(Map.of("base_revision",2,"song_id",next.toString()));
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_relink CHECK(revision<3)");
        assertThatThrownBy(()->linking.patch(auth,device,op,id.toString(),body)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(db.queryForMap("SELECT * FROM recording WHERE id=?",bytes(id))).usingRecursiveComparison().isEqualTo(before);
        assertThat(db.queryForMap("SELECT * FROM song WHERE id=?",bytes(old))).usingRecursiveComparison().isEqualTo(oldBefore);
        assertThat(db.queryForMap("SELECT * FROM song_cloud_selection WHERE song_id=?",bytes(old))).usingRecursiveComparison().isEqualTo(selectionBefore);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(1); // SAVED event remains after rollback.assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(3);
        assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(2);
        String product=db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());db.execute("ALTER TABLE change_log DROP "+(product.equals("MySQL")?"CHECK":"CONSTRAINT")+" reject_relink");
        var response=linking.patch(auth,device,op,id.toString(),body);assertThat(response.status()).isEqualTo(200);var result=JSON.readTree(response.body());
        assertThat(result.get("song_id").asText()).isEqualTo(next.toString());assertThat(result.get("link_revision").asLong()).isEqualTo(2);
        assertThat(JSON.readTree(linking.patch(auth,device,op,id.toString(),body).body())).isEqualTo(result);
        assertThat(db.queryForObject("SELECT representative_recording_id FROM song WHERE id=?",byte[].class,bytes(old))).isNull();
        assertThat(db.queryForObject("SELECT revision FROM song WHERE id=?",Long.class,bytes(old))).isEqualTo(2);
        var selection=db.queryForMap("SELECT * FROM song_cloud_selection WHERE song_id=?",bytes(old));
        for(String field:List.of("representative_id","latest_id","lowest_tier_id"))assertThat(selection.get(field)).isNull();
        assertThat(((Number)selection.get("selection_revision")).longValue()).isEqualTo(2);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE type='POLICY_RECALCULATE'",Integer.class)).isEqualTo(3);
        assertThat(db.queryForList("SELECT aggregate_id FROM job",byte[].class)).usingRecursiveFieldByFieldElementComparator().containsExactlyInAnyOrder(bytes(old),bytes(old),bytes(next));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM change_log WHERE entity_type='SONG'",Integer.class)).isEqualTo(1);
        var after=db.queryForMap("SELECT * FROM recording WHERE id=?",bytes(id));for(String changed:List.of("song_id","link_revision","revision","updated_at")){before.remove(changed);after.remove(changed);}assertThat(after).usingRecursiveComparison().isEqualTo(before);
        assertThat(db.queryForMap("SELECT * FROM recording_asset WHERE recording_id=?",bytes(id))).usingRecursiveComparison().isEqualTo(assetBefore);
        assertThat(db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?",bytes(id))).usingRecursiveComparison().isEqualTo(fileBefore);
        assertThat(db.queryForMap("SELECT * FROM song WHERE id=?",bytes(next))).usingRecursiveComparison().isEqualTo(nextBefore);
        linking.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(Map.of("base_revision",3,"song_id",next.toString())));
        assertThat(db.queryForObject("SELECT link_revision FROM recording WHERE id=?",Long.class,bytes(id))).isEqualTo(2);assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(3);
        linking.patch(auth,device,UUID.randomUUID().toString(),id.toString(),"{\"base_revision\":4,\"song_id\":null}");
        assertThat(db.queryForObject("SELECT link_revision FROM recording WHERE id=?",Long.class,bytes(id))).isEqualTo(3);assertThat(db.queryForObject("SELECT song_id FROM recording WHERE id=?",byte[].class,bytes(id))).isNull();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(4);
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            var start=new java.util.concurrent.CountDownLatch(1);
            java.util.concurrent.Callable<String> task=()->{start.await();try{return Integer.toString(linking.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(Map.of("base_revision",5,"song_id",old.toString()))).status());}catch(com.ksh321.songrecord.api.web.ApiException e){return e.code();}};
            var a=pool.submit(task);var b=pool.submit(task);start.countDown();assertThat(List.of(a.get(20,java.util.concurrent.TimeUnit.SECONDS),b.get(20,java.util.concurrent.TimeUnit.SECONDS))).containsExactlyInAnyOrder("200","REVISION_CONFLICT");
        }catch(Exception e){throw new AssertionError(e);}
        assertThat(db.queryForObject("SELECT link_revision FROM recording WHERE id=?",Long.class,bytes(id))).isEqualTo(4);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(5);
    }
}
