package com.ksh321.songrecord.api.recordings;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Shared transactional scenarios for H2 and fully migrated MySQL (real constraints/triggers). */
public final class RecordingEditingDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private RecordingEditingDatabaseChecks(){}
    public static void verify(JdbcTemplate db,RecordingDrafts drafts,RecordingEditing editing,String auth,String device,UUID owner){
        UUID song=UUID.randomUUID(),recording=UUID.randomUUID(),tag=UUID.randomUUID();
        db.update("INSERT INTO song(id,user_id,source_type,title,artist,note,lifecycle_state) VALUES(?,?,'MANUAL','song','artist','','ACTIVE')",bytes(song),bytes(owner));
        db.update("INSERT INTO tag(id,user_id,name,normalized_name_key) VALUES(?,?,'old tag',?)",bytes(tag),bytes(owner),"old tag".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        var create=Map.of("id",recording.toString(),"metadata_state","DRAFT","song_id",song.toString(),"recorded_at","2026-09-28T07:00:00Z","timezone_id","Asia/Seoul","timezone_offset_minutes",540);
        assertThat(drafts.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(create)).status()).isEqualTo(201);
        var file=Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        var save=Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","title","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file);
        assertThat(editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(save)).status()).isEqualTo(200);
        var fileBefore=db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?",bytes(recording));
        var songBefore=db.queryForMap("SELECT * FROM song WHERE id=?",bytes(song));
        var change=new LinkedHashMap<String,Object>(Map.of("base_revision",2,"note","a\r\nb","version_code","LIVE","key_mode","MALE","key_shift",-2,"recorded_at","2026-09-27T07:00:00.123Z","tag_ids",List.of(tag.toString()),"condition_code","GOOD"));
        String op=UUID.randomUUID().toString(),body=JSON.writeValueAsString(change);
        // Failure after recording, tags, history and job: every participant must roll back.
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_recording_edit CHECK(revision<3)");
        assertThatThrownBy(()->editing.patch(auth,device,op,recording.toString(),body)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(db.queryForObject("SELECT revision FROM recording WHERE id=?",Long.class,bytes(recording))).isEqualTo(2);
        for(String table:List.of("recording_tag","recording_time_correction"))assertThat(db.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class)).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(1); // only the committed SAVED event
        assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(2);
        assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(2);
        db.execute(db.getDataSource()!=null && product(db).equals("MySQL")?"ALTER TABLE change_log DROP CHECK reject_recording_edit":"ALTER TABLE change_log DROP CONSTRAINT reject_recording_edit");
        var result=editing.patch(auth,device,op,recording.toString(),body);assertThat(result.status()).isEqualTo(200);
        assertThat(JSON.readTree(result.body()).get("note").asText()).isEqualTo("a\nb");
        assertThat(JSON.readTree(result.body()).get("revision").asInt()).isEqualTo(3);
        assertThat(JSON.readTree(result.body()).get("condition_name_snapshot").asText()).isEqualTo("좋음");
        assertThat(JSON.readTree(editing.patch(auth,device,op,recording.toString(),body).body())).isEqualTo(JSON.readTree(result.body()));
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_time_correction",Integer.class)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT revision FROM recording_time_correction",Long.class)).isEqualTo(3);
        assertThat(db.queryForObject("SELECT actor_device_id FROM recording_time_correction",byte[].class)).isEqualTo(bytes(UUID.fromString(device)));
        assertThat(db.queryForObject("SELECT old_recorded_at FROM recording_time_correction",java.sql.Timestamp.class).toLocalDateTime().toString()).isEqualTo("2026-09-28T07:00");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE type='POLICY_RECALCULATE' AND state='QUEUED'",Integer.class)).isEqualTo(2);
        assertThat(db.queryForList("SELECT aggregate_id FROM job",byte[].class)).usingRecursiveFieldByFieldElementComparator().containsExactlyInAnyOrder(bytes(song),bytes(song));
        assertThat(db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?",bytes(recording))).usingRecursiveComparison().isEqualTo(fileBefore);
        assertThat(db.queryForMap("SELECT * FROM song WHERE id=?",bytes(song))).usingRecursiveComparison().isEqualTo(songBefore);
        db.update("UPDATE tag SET name='new tag',archived_at=CURRENT_TIMESTAMP WHERE id=?",bytes(tag));
        var keep=Map.of("base_revision",3,"tag_ids",List.of(tag.toString()),"condition_code","GOOD","recorded_at","2026-09-27T07:00:00.123Z");
        var kept=editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(keep));
        assertThat(JSON.readTree(kept.body()).get("tags").get(0).get("name_snapshot").asText()).isEqualTo("old tag");
        assertThat(JSON.readTree(kept.body()).get("condition_name_snapshot").asText()).isEqualTo("좋음");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_time_correction",Integer.class)).isEqualTo(1);
        var clear=new LinkedHashMap<String,Object>();clear.put("base_revision",4);clear.put("condition_code",null);clear.put("tag_ids",List.of());
        assertThat(editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(clear)).status()).isEqualTo(200);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_tag",Integer.class)).isZero();
        assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording WHERE id=?",String.class,bytes(recording))).isNull();
        assertThatThrownBy(()->editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(Map.of("base_revision",5,"tag_ids",List.of(tag.toString()))))).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("TAG_ARCHIVED"));
        // Two requests editing the same revision cannot both win, even with different op IDs.
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            var start=new java.util.concurrent.CountDownLatch(1);
            java.util.concurrent.Callable<String> edit=()->{
                start.await();
                try{return Integer.toString(editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(Map.of("base_revision",5,"note",UUID.randomUUID().toString()))).status());}
                catch(com.ksh321.songrecord.api.web.ApiException e){return e.code();}
            };
            var a=pool.submit(edit);var b=pool.submit(edit);start.countDown();
            assertThat(List.of(a.get(20,java.util.concurrent.TimeUnit.SECONDS),b.get(20,java.util.concurrent.TimeUnit.SECONDS))).containsExactlyInAnyOrder("200","REVISION_CONFLICT");
        }catch(Exception e){throw new AssertionError(e);}
        assertThat(db.queryForObject("SELECT revision FROM recording WHERE id=?",Long.class,bytes(recording))).isEqualTo(6);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_time_correction",Integer.class)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(2);

    }
    private static String product(JdbcTemplate db){return db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());}
}
