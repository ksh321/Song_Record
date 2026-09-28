package com.ksh321.songrecord.api.recordings;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Executes unchanged on H2 and MySQL with all production migrations and triggers. */
public final class RecordingRatingDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private RecordingRatingDatabaseChecks(){}
    public static void verify(JdbcTemplate db,RecordingDrafts drafts,RecordingEditing editing,RecordingRating rating,String auth,String device,UUID owner){
        UUID song=UUID.randomUUID(),id=UUID.randomUUID();
        db.update("INSERT INTO song(id,user_id,source_type,title,artist,note,song_tier,lifecycle_state) VALUES(?,?,'MANUAL','song','artist','','S','ACTIVE')",bytes(song),bytes(owner));
        drafts.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",id.toString(),"metadata_state","DRAFT","song_id",song.toString(),"recorded_at","2026-09-28T07:00:00Z","timezone_id","Asia/Seoul","timezone_offset_minutes",540)));
        var file=Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        editing.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","title","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file)));
        var songBefore=db.queryForMap("SELECT * FROM song WHERE id=?",bytes(song));var fileBefore=db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?",bytes(id));
        var metadataBefore=db.queryForMap("SELECT song_id,origin_device_id,recorded_at,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,note,link_revision FROM recording WHERE id=?",bytes(id));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_asset",Integer.class)).isZero();
        String op=UUID.randomUUID().toString(),body="{\"base_revision\":2,\"tier\":\"D\"}";
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_rating CHECK(revision<3)");
        assertThatThrownBy(()->rating.patch(auth,device,op,id.toString(),body)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(db.queryForObject("SELECT revision FROM recording WHERE id=?",Long.class,bytes(id))).isEqualTo(2);
        assertThat(db.queryForObject("SELECT tier FROM recording WHERE id=?",String.class,bytes(id))).isNull();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(2);
        assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(2);
        String product=db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());
        db.execute("ALTER TABLE change_log DROP "+(product.equals("MySQL")?"CHECK":"CONSTRAINT")+" reject_rating");
        var response=rating.patch(auth,device,op,id.toString(),body);assertThat(response.status()).isEqualTo(200);
        assertThat(JSON.readTree(response.body()).get("tier").asText()).isEqualTo("D");
        assertThat(JSON.readTree(rating.patch(auth,device,op,id.toString(),body).body())).isEqualTo(JSON.readTree(response.body()));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE type='POLICY_RECALCULATE' AND state='QUEUED'",Integer.class)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT aggregate_id FROM job",byte[].class)).isEqualTo(bytes(song));
        assertThat(JSON.readTree(db.queryForObject("SELECT payload FROM job",String.class)).get("reason").asText()).isEqualTo("RECORDING_TIER_CHANGED");
        assertThatThrownBy(()->rating.patch(auth,device,op,id.toString(),"{\"base_revision\":2,\"tier\":\"A\"}")).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("IDEMPOTENCY_CONFLICT"));
        // New op with the same rating advances revision, but cannot change policy selection.
        rating.patch(auth,device,UUID.randomUUID().toString(),id.toString(),"{\"base_revision\":3,\"tier\":\"D\"}");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(1);
        // Explicit null clears the rating and must enqueue a recalculation too.
        rating.patch(auth,device,UUID.randomUUID().toString(),id.toString(),"{\"base_revision\":4,\"tier\":null}");
        assertThat(db.queryForObject("SELECT tier FROM recording WHERE id=?",String.class,bytes(id))).isNull();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(2);
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            var start=new java.util.concurrent.CountDownLatch(1);
            java.util.concurrent.Callable<String> task=()->{start.await();try{return Integer.toString(rating.patch(auth,device,UUID.randomUUID().toString(),id.toString(),"{\"base_revision\":5,\"tier\":\"B\"}").status());}catch(com.ksh321.songrecord.api.web.ApiException e){return e.code();}};
            var a=pool.submit(task);var b=pool.submit(task);start.countDown();
            assertThat(List.of(a.get(20,java.util.concurrent.TimeUnit.SECONDS),b.get(20,java.util.concurrent.TimeUnit.SECONDS))).containsExactlyInAnyOrder("200","REVISION_CONFLICT");
        }catch(Exception e){throw new AssertionError(e);}
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(3);
        assertThat(db.queryForObject("SELECT revision FROM recording WHERE id=?",Long.class,bytes(id))).isEqualTo(6);
        assertThat(db.queryForMap("SELECT * FROM song WHERE id=?",bytes(song))).usingRecursiveComparison().isEqualTo(songBefore);
        assertThat(db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?",bytes(id))).usingRecursiveComparison().isEqualTo(fileBefore);
        assertThat(db.queryForMap("SELECT song_id,origin_device_id,recorded_at,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,note,link_revision FROM recording WHERE id=?",bytes(id))).usingRecursiveComparison().isEqualTo(metadataBefore);
    }
}
