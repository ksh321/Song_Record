package com.ksh321.songrecord.api.retention;

import java.time.Instant;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Runs unchanged against isolated H2 and fully migrated MySQL; all rows are synthetic. */
public final class RetentionCandidateDatabaseChecks {
    private RetentionCandidateDatabaseChecks() {}
    public static UUID account(JdbcTemplate db) {
        UUID id = UUID.randomUUID(); db.update("INSERT INTO app_user(id) VALUES(?)", bytes(id)); return id;
    }
    public static UUID device(JdbcTemplate db, UUID owner) {
        UUID id = UUID.randomUUID(); db.update("INSERT INTO device(id,user_id,display_name,last_seen_at) VALUES(?,?,'test',CURRENT_TIMESTAMP)", bytes(id), bytes(owner)); return id;
    }
    public static UUID song(JdbcTemplate db, UUID owner) {
        UUID id = UUID.randomUUID(); db.update("INSERT INTO song(id,user_id,source_type,title,artist,note) VALUES(?,?,'MANUAL','song','artist','')", bytes(id), bytes(owner)); return id;
    }
    public static UUID recording(JdbcTemplate db, UUID owner, UUID device, UUID song, boolean saved, boolean spec, String integrity) {
        UUID id = UUID.randomUUID();
        db.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,key_mode,key_shift,note,recorded_at,timezone_id,timezone_offset_minutes) VALUES(?,?,?,?,'title','artist','ORIGINAL',0,'','2026-10-08 00:00:00.123','UTC',0)", bytes(id),bytes(owner),bytes(device),song==null?null:bytes(song));
        if (spec) db.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,6291456,361000,'AAC_LC',48000,1,?)", bytes(id),bytes(owner),"a".repeat(64),integrity);
        if (saved) db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(id));
        return id;
    }
    public static void verifyRepresentative(JdbcTemplate db) {
        var roles = new RetentionRoles(new RetentionCandidates(db));
        UUID owner=account(db), other=account(db), a=device(db,owner), b=device(db,owner);
        UUID song=song(db,owner);
        UUID chosen=recording(db,owner,b,song,true,true,"RECOVERED");
        UUID latest=recording(db,owner,a,song,true,true,"VALIDATED");
        db.update("UPDATE recording SET tier='S',recorded_at='2026-10-09 00:00:00' WHERE id=?",bytes(latest));
        assertThat(roles.representative(owner,song)).isEmpty(); // No highest-tier/latest fallback.
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(chosen),bytes(song));
        var selected=roles.representative(owner,song).orElseThrow();
        assertThat(selected.role()).isEqualTo(RetentionRoles.Role.REPRESENTATIVE);
        assertThat(selected.candidate().recordingId()).isEqualTo(chosen);
        assertThat(selected.candidate().originDeviceId()).isEqualTo(b);
        assertThat(roles.representative(other,song)).isEmpty();
        db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(chosen));
        assertThat(roles.representative(owner,song)).isEmpty(); // No replacement, pointer is not mutated.
        assertThat(db.queryForObject("SELECT representative_recording_id FROM song WHERE id=?",byte[].class,bytes(song))).isEqualTo(bytes(chosen));
        db.update("UPDATE song SET representative_recording_id=NULL WHERE id=?",bytes(song));
        assertThat(roles.representative(owner,song)).isEmpty();
    }
    public static void verify(JdbcTemplate db) {
        var query = new RetentionCandidates(db);
        UUID owner=account(db), other=account(db), a=device(db,owner), b=device(db,owner), foreign=device(db,other);
        UUID song=song(db,owner), another=song(db,owner), theirs=song(db,other);
        UUID first=recording(db,owner,a,song,true,true,"VALIDATED");
        UUID remote=recording(db,owner,b,song,true,true,"RECOVERED");
        db.update("UPDATE recording SET version_code='LIVE',key_mode='MALE',key_shift=2,tier='D' WHERE id=?",bytes(remote));
        recording(db,owner,a,song,false,true,"VALIDATED"); // DRAFT has a completed file, still ineligible.
        recording(db,owner,a,song,false,false,"VALIDATED");
        recording(db,owner,a,null,true,true,"VALIDATED");
        recording(db,owner,a,another,true,true,"VALIDATED");
        recording(db,other,foreign,theirs,true,true,"VALIDATED");
        UUID trashed=recording(db,owner,a,song,true,true,"VALIDATED");
        db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(trashed));
        var found=query.forSong(owner,song);
        assertThat(found).extracting(RetentionCandidates.Candidate::recordingId).containsExactlyInAnyOrder(first,remote);
        assertThat(found.stream().filter(c->c.recordingId().equals(remote)).findFirst().orElseThrow().originDeviceId()).isEqualTo(b);
        assertThat(found).allSatisfy(c->{assertThat(c.recordedAt()).isEqualTo(Instant.parse("2026-10-08T00:00:00.123Z"));assertThat(c.file().sizeBytes()).isEqualTo(6291456);});
        assertThatThrownBy(()->found.clear()).isInstanceOf(UnsupportedOperationException.class);
        assertThat(query.forSong(other,song)).isEmpty(); assertThat(query.forSong(owner,theirs)).isEmpty();
        assertThat(query.forSong(owner,UUID.randomUUID())).isEmpty();
        db.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(song));
        assertThat(query.forSong(owner,song)).isEmpty();
        db.update("UPDATE song SET lifecycle_state='ACTIVE',deleted_at=NULL WHERE id=?",bytes(song));
        assertThat(query.forSong(owner,song)).hasSize(2);
        db.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));
        assertThat(query.forSong(owner,song)).isEmpty();
    }
}
