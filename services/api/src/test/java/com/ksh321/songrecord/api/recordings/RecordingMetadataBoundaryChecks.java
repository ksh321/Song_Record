package com.ksh321.songrecord.api.recordings;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.LinkedMultiValueMap;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Runs against H2 and the full MySQL schema; storage restrictions must not gate metadata. */
public final class RecordingMetadataBoundaryChecks {
    private static final JsonMapper JSON = new JsonMapper();
    private RecordingMetadataBoundaryChecks() {}

    public static void verify(JdbcTemplate db, RecordingDrafts drafts, RecordingEditing editing,
            RecordingRating rating, RecordingLinking linking, RecordingListing listing,
            String auth, String device, UUID owner, String reason) {
        byte[] user = bytes(owner);
        if (db.queryForObject("SELECT COUNT(*) FROM user_entitlement WHERE user_id=?", Integer.class, user) == 0)
            db.update("INSERT INTO user_entitlement(user_id) VALUES(?)", user);
        if (db.queryForObject("SELECT COUNT(*) FROM storage_usage WHERE user_id=?", Integer.class, user) == 0)
            db.update("INSERT INTO storage_usage(user_id) VALUES(?)", user);
        // Each case isolates one admission restriction. No file worker is run here.
        db.update("UPDATE user_entitlement SET quota_bytes=?,pinned_limit=? WHERE user_id=?",
                reason.equals("QUOTA") ? 100 : 1000000000, reason.equals("PIN_LIMIT") ? 0 : 10, user);
        db.update("UPDATE storage_usage SET used_bytes=100,reserved_bytes=0 WHERE user_id=?", user);
        db.update("UPDATE global_storage_usage SET upload_locked=? WHERE id=1", reason.equals("BUDGET"));
        var entitlement = db.queryForMap("SELECT * FROM user_entitlement WHERE user_id=?", user);
        var usage = db.queryForMap("SELECT * FROM storage_usage WHERE user_id=?", user);
        var global = db.queryForMap("SELECT * FROM global_storage_usage WHERE id=1");
        UUID id = UUID.randomUUID(), song = UUID.randomUUID();
        db.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,lifecycle_state) VALUES(?,?,'MANUAL','song','artist','NORMAL','','ACTIVE')", bytes(song), user);
        var songBefore = db.queryForMap("SELECT * FROM song WHERE id=?", bytes(song));
        String create = JSON.writeValueAsString(Map.of("id", id.toString(), "metadata_state", "DRAFT",
                "recorded_at", "2026-09-28T07:00:00Z", "timezone_id", "Asia/Seoul", "timezone_offset_minutes", 540));
        var draft = drafts.create(auth, device, UUID.randomUUID().toString(), create);
        assertThat(draft.status()).isEqualTo(201);
        assertThat(JSON.readTree(draft.body()).get("title_snapshot").isNull()).isTrue();
        assertThat(JSON.readTree(draft.body()).get("version_code").asText()).isEqualTo("NORMAL");
        db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,blocked_reason) VALUES(?,?,'QUEUED',?)", bytes(id), user, reason);
        var asset = db.queryForMap("SELECT * FROM recording_asset WHERE recording_id=?", bytes(id));
        // User edits before selecting a song must survive selecting it (V45).
        assertThat(editing.patch(auth, device, UUID.randomUUID().toString(), id.toString(),
                JSON.writeValueAsString(Map.of("base_revision", 1, "key_mode", "FEMALE", "key_shift", 3, "version_code", "LIVE", "note", "keep input"))).status()).isEqualTo(200);
        assertThat(linking.patch(auth, device, UUID.randomUUID().toString(), id.toString(),
                JSON.writeValueAsString(Map.of("base_revision", 2, "song_id", song.toString()))).status()).isEqualTo(200);
        var selected = db.queryForMap("SELECT key_mode,key_shift,version_code,note,title_snapshot FROM recording WHERE id=?", bytes(id));
        assertThat(selected.get("key_mode")).isEqualTo("FEMALE");
        assertThat(((Number)selected.get("key_shift")).intValue()).isEqualTo(3);
        assertThat(selected.get("version_code")).isEqualTo("LIVE");
        assertThat(selected.get("note")).isEqualTo("keep input");
        assertThat(selected.get("title_snapshot")).isNull();
        var file = Map.of("size_bytes", 100, "duration_ms", 1000, "sha256", "a".repeat(64),
                "codec", "AAC_LC", "sample_rate", 48000, "channels", 1, "capture_integrity", "VALIDATED");
        String save = JSON.writeValueAsString(Map.of("base_revision", 3, "metadata_state", "SAVED",
                "title_snapshot", "capture title", "artist_snapshot", "capture artist", "file", file));
        String op = UUID.randomUUID().toString();
        var saved = editing.patch(auth, device, op, id.toString(), save);
        assertThat(saved.status()).isEqualTo(200);
        assertThat(editing.patch(auth, device, op, id.toString(), save)).isEqualTo(saved);
        var spec = db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?", bytes(id));
        assertThat(rating.patch(auth, device, UUID.randomUUID().toString(), id.toString(),
                "{\"base_revision\":4,\"tier\":\"A\"}").status()).isEqualTo(200);
        assertThat(editing.patch(auth, device, UUID.randomUUID().toString(), id.toString(),
                "{\"base_revision\":5,\"note\":\"edited while blocked\",\"version_code\":\"MR\"}").status()).isEqualTo(200);
        var page = listing.list(auth, device, new LinkedMultiValueMap<>());
        var item = page.items().stream().filter(v -> v.get("id").equals(id.toString())).findFirst().orElseThrow();
        assertThat(item.get("metadata_state")).isEqualTo("SAVED");
        assertThat(item.get("tier")).isEqualTo("A");
        assertThat(item.get("version_code")).isEqualTo("MR");
        assertThat(item.get("note")).isEqualTo("edited while blocked");
        var cloud = (Map<?,?>) item.get("cloud");
        assertThat(cloud.get("state")).isEqualTo("QUEUED");
        assertThat(cloud.get("blocked_reason")).isEqualTo(reason);
        assertThat(cloud.get("stored")).isEqualTo(false);
        var afterAsset=db.queryForMap("SELECT * FROM recording_asset WHERE recording_id=?",bytes(id));
        assertThat(((Number)afterAsset.get("cloud_revision")).longValue()).isEqualTo(((Number)asset.get("cloud_revision")).longValue()+1);
        for(String field:List.of("cloud_revision","updated_at")){asset.remove(field);afterAsset.remove(field);}
        assertThat(afterAsset).usingRecursiveComparison().isEqualTo(asset);
        assertThat(db.queryForMap("SELECT * FROM recording_file_spec WHERE recording_id=?", bytes(id))).usingRecursiveComparison().isEqualTo(spec);
        assertThat(db.queryForMap("SELECT * FROM song WHERE id=?", bytes(song))).usingRecursiveComparison().isEqualTo(songBefore);
        assertThat(db.queryForMap("SELECT * FROM user_entitlement WHERE user_id=?", user)).usingRecursiveComparison().isEqualTo(entitlement);
        assertThat(db.queryForMap("SELECT * FROM storage_usage WHERE user_id=?", user)).usingRecursiveComparison().isEqualTo(usage);
        assertThat(db.queryForMap("SELECT * FROM global_storage_usage WHERE id=1")).usingRecursiveComparison().isEqualTo(global);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM change_log WHERE entity_id=?", Integer.class, bytes(id))).isEqualTo(6);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM pin_slot WHERE user_id=?", Integer.class, user)).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE aggregate_id=? AND type='POLICY_RECALCULATE'", Integer.class, bytes(song))).isGreaterThanOrEqualTo(1);
    }
}
