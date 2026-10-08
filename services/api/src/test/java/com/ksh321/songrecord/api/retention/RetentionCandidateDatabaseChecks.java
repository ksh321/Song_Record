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
        return recordingWithId(db, owner, device, song, saved, spec, integrity, UUID.randomUUID());
    }
    public static UUID recordingWithId(JdbcTemplate db, UUID owner, UUID device, UUID song, boolean saved, boolean spec, String integrity, UUID id) {
        db.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,key_mode,key_shift,note,recorded_at,timezone_id,timezone_offset_minutes,lifecycle_state) VALUES(?,?,?,?,'title','artist','ORIGINAL',0,'','2026-10-08 00:00:00.123','UTC',0,'ACTIVE')", bytes(id),bytes(owner),bytes(device),song==null?null:bytes(song));
        if (spec) db.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,6291456,361000,'AAC_LC',48000,1,?)", bytes(id),bytes(owner),"a".repeat(64),integrity);
        if (saved) db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(id));
        return id;
    }
    public static void verifySelectionStore(JdbcTemplate db) {
        var store=new RetentionSelectionStore(db,new org.springframework.jdbc.datasource.DataSourceTransactionManager(db.getDataSource()));
        UUID owner=account(db), dev=device(db,owner), song=song(db,owner);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
        UUID a=recording(db,owner,dev,song,true,true,"VALIDATED");
        db.update("UPDATE recording SET tier='D' WHERE id=?",bytes(a));
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(a),bytes(song));
        // Concurrent first creation/retry: one account lock, one stored row, one stable revision.
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)) {
            var first=pool.submit(()->store.recalculate(owner,song).orElseThrow());
            var second=pool.submit(()->store.recalculate(owner,song).orElseThrow());
            var one=first.get(15,java.util.concurrent.TimeUnit.SECONDS);
            assertThat(second.get(15,java.util.concurrent.TimeUnit.SECONDS)).isEqualTo(one);
            assertThat(one.revision()).isEqualTo(1);
            assertThat(one.recordingIds()).containsExactly(a);
            assertThat(one.ids()).isEqualTo(new RetentionRoles.Ids(a,a,a));
            assertThatThrownBy(()->one.recordingIds().clear()).isInstanceOf(UnsupportedOperationException.class);
        } catch(Exception e) {throw new AssertionError(e);}
        UUID b=recording(db,owner,dev,song,true,true,"VALIDATED");
        UUID c=recording(db,owner,dev,song,true,true,"RECOVERED");
        db.update("UPDATE recording SET tier='A' WHERE id=?",bytes(a));
        db.update("UPDATE recording SET tier='S',recorded_at='2026-10-09 00:00:00',key_mode='MALE',key_shift=2,version_code='LIVE' WHERE id=?",bytes(b));
        db.update("UPDATE recording SET tier='D',recorded_at='2026-10-07 00:00:00',key_mode='FEMALE',key_shift=-2 WHERE id=?",bytes(c));
        var split=store.recalculate(owner,song).orElseThrow();
        assertThat(split.ids()).isEqualTo(new RetentionRoles.Ids(a,b,c));
        assertThat(split.revision()).isEqualTo(2);
        assertThat(split.recordingIds()).containsExactlyInAnyOrder(a,b,c);
        assertThat(store.recalculate(owner,song).orElseThrow()).isEqualTo(split);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM song_cloud_selection WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(1);
        // Persisted three role columns represent their ID union, not three copies or per-key slots.
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording r JOIN song_cloud_selection s ON s.user_id=r.user_id AND s.song_id=r.song_id WHERE r.user_id=? AND (r.id=s.representative_id OR r.id=s.latest_id OR r.id=s.lowest_tier_id)",Integer.class,bytes(owner))).isEqualTo(3);
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(c),bytes(song));
        var merged=store.recalculate(owner,song).orElseThrow();assertThat(merged.recordingIds()).containsExactlyInAnyOrder(b,c);
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(b),bytes(song));
        var remapped=store.recalculate(owner,song).orElseThrow();
        assertThat(remapped.recordingIds()).isEqualTo(merged.recordingIds());
        assertThat(remapped.revision()).isEqualTo(merged.revision()+1); // Mapping changed despite equal union.
        assertThat(store.recalculate(UUID.randomUUID(),song)).isEmpty();
        UUID foreignOwner=account(db);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(foreignOwner));
        assertThat(store.recalculate(foreignOwner,song)).isEmpty();
        assertThat(store.recalculate(owner,UUID.randomUUID())).isEmpty();
        db.update("UPDATE song SET representative_recording_id=NULL WHERE id=?",bytes(song));
        db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE user_id=?",bytes(owner));
        var empty=store.recalculate(owner,song).orElseThrow();assertThat(empty.recordingIds()).isEmpty();
        long revision=empty.revision();
        // Force the SQL update itself to fail: no partial role/version update may survive.
        db.execute("ALTER TABLE song_cloud_selection ADD CONSTRAINT ck_test_selection_revision CHECK(selection_revision<="+revision+")");
        try {
            db.update("UPDATE recording SET lifecycle_state='ACTIVE',deleted_at=NULL WHERE id=?",bytes(a));
            assertThatThrownBy(()->store.recalculate(owner,song)).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(db.queryForObject("SELECT selection_revision FROM song_cloud_selection WHERE song_id=?",Long.class,bytes(song))).isEqualTo(revision);
            assertThat(db.queryForObject("SELECT latest_id FROM song_cloud_selection WHERE song_id=?",byte[].class,bytes(song))).isNull();
        } finally {
            String engine=db.execute((org.springframework.jdbc.core.ConnectionCallback<String>)connection -> connection.getMetaData().getDatabaseProductName());
            db.execute("ALTER TABLE song_cloud_selection DROP "+("MySQL".equals(engine)?"CHECK":"CONSTRAINT")+" ck_test_selection_revision");
        }
        var restored=store.recalculate(owner,song).orElseThrow();assertThat(restored.revision()).isEqualTo(revision+1);
        db.update("UPDATE song_cloud_selection SET selection_revision=? WHERE song_id=?",Long.MAX_VALUE,bytes(song));
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(a),bytes(song));
        assertThatThrownBy(()->store.recalculate(owner,song)).isInstanceOf(IllegalStateException.class).hasMessage("Selection revision exhausted");
        assertThat(db.queryForObject("SELECT representative_id FROM song_cloud_selection WHERE song_id=?",byte[].class,bytes(song))).isNull();
        var tx=new org.springframework.transaction.support.TransactionTemplate(new org.springframework.jdbc.datasource.DataSourceTransactionManager(db.getDataSource()));
        assertThatThrownBy(()->tx.execute(status->store.recalculate(owner,song))).isInstanceOf(IllegalStateException.class);
        db.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));
        assertThat(store.recalculate(owner,song)).isEmpty();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_file_spec WHERE user_id=?",Integer.class,bytes(owner))).isEqualTo(3);
    }
    public static void verifyLowestTier(JdbcTemplate db) {
        var roles=new RetentionRoles(new RetentionCandidates(db));
        UUID owner=account(db), dev=device(db,owner), song=song(db,owner);
        db.update("UPDATE song SET song_tier='D' WHERE id=?",bytes(song));
        recording(db,owner,dev,song,true,true,"VALIDATED");
        assertThat(roles.lowestTier(owner,song)).isEmpty(); // Unrated is not the song's tier.
        var ids=new ArrayList<UUID>();
        for (String tier:List.of("D","C","B","A","S")) {
            UUID id=recording(db,owner,dev,song,true,true,"VALIDATED");ids.add(id);
            db.update("UPDATE recording SET tier=? WHERE id=?",tier,bytes(id));
        }
        for (UUID id:ids) {
            var selected=roles.lowestTier(owner,song).orElseThrow();
            assertThat(selected.role()).isEqualTo(RetentionRoles.Role.LOWEST_TIER);
            assertThat(selected.candidate().recordingId()).isEqualTo(id);
            db.update("UPDATE recording SET tier=NULL WHERE id=?",bytes(id));
        }
        assertThat(roles.lowestTier(owner,song)).isEmpty();
        UUID low=UUID.fromString("7fffffff-ffff-ffff-ffff-ffffffffff01");
        UUID high=UUID.fromString("80000000-0000-0000-0000-000000000001");
        recordingWithId(db,owner,dev,song,true,true,"VALIDATED",high);
        recordingWithId(db,owner,dev,song,true,true,"RECOVERED",low);
        db.update("UPDATE recording SET tier='D' WHERE id IN (?,?)",bytes(low),bytes(high));
        assertThat(roles.lowestTier(owner,song).orElseThrow().candidate().recordingId()).isEqualTo(low);
        db.update("UPDATE recording SET recorded_at='2026-10-08 00:00:00.124' WHERE id=?",bytes(high));
        assertThat(roles.lowestTier(owner,song).orElseThrow().candidate().recordingId()).isEqualTo(high);
        db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(high));
        assertThat(roles.lowestTier(owner,song).orElseThrow().candidate().recordingId()).isEqualTo(low);
        assertThat(roles.lowestTier(UUID.randomUUID(),song)).isEmpty();
        assertThat(roles.lowestTier(owner,UUID.randomUUID())).isEmpty();
    }
    public static void verifyLatest(JdbcTemplate db) {
        var roles=new RetentionRoles(new RetentionCandidates(db));
        UUID owner=account(db), a=device(db,owner), b=device(db,owner), song=song(db,owner);
        assertThat(roles.latest(owner,song)).isEmpty();
        UUID low=UUID.fromString("7fffffff-ffff-ffff-ffff-ffffffffffff");
        UUID high=UUID.fromString("80000000-0000-0000-0000-000000000000");
        // Insert high first, low second, on different devices; tie order must be unsigned ID order.
        recordingWithId(db,owner,a,song,true,true,"VALIDATED",high);
        recordingWithId(db,owner,b,song,true,true,"RECOVERED",low);
        db.update("UPDATE recording SET tier='S',revision=99 WHERE id=?",bytes(high));
        var selected=roles.latest(owner,song).orElseThrow();
        assertThat(selected.role()).isEqualTo(RetentionRoles.Role.LATEST);
        assertThat(selected.candidate().recordingId()).isEqualTo(low);
        db.update("UPDATE recording SET recorded_at='2026-10-08 00:00:00.124' WHERE id=?",bytes(high));
        assertThat(roles.latest(owner,song).orElseThrow().candidate().recordingId()).isEqualTo(high);
        db.update("UPDATE recording SET recorded_at='2026-10-07 23:59:59.999' WHERE id=?",bytes(high));
        assertThat(roles.latest(owner,song).orElseThrow().candidate().recordingId()).isEqualTo(low);
        UUID draft=recording(db,owner,a,song,false,true,"VALIDATED");
        db.update("UPDATE recording SET recorded_at='2030-01-01 00:00:00' WHERE id=?",bytes(draft));
        assertThat(roles.latest(owner,song).orElseThrow().candidate().recordingId()).isEqualTo(low);
        assertThat(roles.latest(UUID.randomUUID(),song)).isEmpty();
        assertThat(roles.latest(owner,UUID.randomUUID())).isEmpty();
        var before=db.queryForList("SELECT id,revision,recorded_at FROM recording WHERE user_id=? ORDER BY id",bytes(owner));
        assertThat(roles.latest(owner,song)).isEqualTo(roles.latest(owner,song));
        assertThat(db.queryForList("SELECT id,revision,recorded_at FROM recording WHERE user_id=? ORDER BY id",bytes(owner)))
            .usingRecursiveComparison().isEqualTo(before);
        db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE user_id=?",bytes(owner));
        assertThat(roles.latest(owner,song)).isEmpty();
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
