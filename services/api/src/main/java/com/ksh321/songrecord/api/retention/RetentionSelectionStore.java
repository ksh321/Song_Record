package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.locking.LockOrder;
import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.uuid;

/** Trusted server worker entry. Not an HTTP authorization boundary. Owns one short transaction.
 * Job completion joins a fresh transaction; no asset/pin/hold/file changes or external work here. */
@Component
@Profile("!bootstrap")
public final class RetentionSelectionStore {
    private final JdbcTemplate jdbc;
    private final RetentionCandidates candidates;
    private final TransactionTemplate transaction;
    public RetentionSelectionStore(JdbcTemplate jdbc, PlatformTransactionManager manager) {
        this.jdbc=jdbc;this.candidates=new RetentionCandidates(jdbc);
        transaction=new TransactionTemplate(manager);
        transaction.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
    }
    public Optional<Snapshot> recalculate(UUID owner, UUID song) {
        Objects.requireNonNull(owner);Objects.requireNonNull(song);
        // Never join an older snapshot or invert locks of an enclosing mutation.
        LockOrder.requireOutsideTransaction();
        return transaction.execute(status -> locked(owner,song));
    }
    /** Called only inside JobQueue.complete; lease loss rolls this write back with job completion. */
    public Optional<Snapshot> recalculateInJob(UUID owner,UUID song) {
        if(!org.springframework.transaction.support.TransactionSynchronizationManager.hasResource(jdbc.getDataSource())
            || !Integer.valueOf(TransactionDefinition.ISOLATION_READ_COMMITTED).equals(
                org.springframework.transaction.support.TransactionSynchronizationManager.getCurrentTransactionIsolationLevel()))
            throw new IllegalStateException("Job database transaction required");
        return locked(Objects.requireNonNull(owner),Objects.requireNonNull(song));
    }
    private Optional<Snapshot> locked(UUID owner,UUID song) {
            if (!active(owner)) return Optional.empty();
            LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());
            if(jdbc.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner)).size()!=1)
                throw new IllegalStateException("Account sync state is missing");
            if (!active(owner)) return Optional.empty();
            LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/0/"+song);
            var songs=jdbc.query("SELECT representative_recording_id,lifecycle_state FROM song WHERE user_id=? AND id=? FOR UPDATE",
                (rs,n)->new Song(id(rs.getBytes(1)),"ACTIVE".equals(rs.getString(2))),bytes(owner),bytes(song));
            if(songs.isEmpty()) return Optional.empty();
            // All participating account metadata writers hold USER_SYNC. One fresh candidate read.
            var selected=songs.getFirst().active()?RetentionRoles.calculate(candidates.forSong(owner,song),songs.getFirst().representative()):new RetentionRoles.Ids(null,null,null);
            LockOrder.before(LockOrder.Rank.SONG_SELECTION,owner+"/"+song);
            var stored=jdbc.query("SELECT representative_id,latest_id,lowest_tier_id,selection_revision FROM song_cloud_selection WHERE user_id=? AND song_id=? FOR UPDATE",
                (rs,n)->new Snapshot(new RetentionRoles.Ids(id(rs.getBytes(1)),id(rs.getBytes(2)),id(rs.getBytes(3))),rs.getLong(4)),bytes(owner),bytes(song));
            if(stored.isEmpty()) {
                jdbc.update("INSERT INTO song_cloud_selection(song_id,user_id,representative_id,latest_id,lowest_tier_id,selection_revision) VALUES(?,?,?,?,?,1)",
                    bytes(song),bytes(owner),value(selected.representative()),value(selected.latest()),value(selected.lowestTier()));
                return Optional.of(new Snapshot(selected,1));
            }
            var previous=stored.getFirst();
            if(previous.ids().equals(selected))return Optional.of(previous); // Retry/no-op does not consume a version.
            if(previous.revision()==Long.MAX_VALUE)throw new IllegalStateException("Selection revision exhausted");
            long next=previous.revision()+1;
            int changed=jdbc.update("UPDATE song_cloud_selection SET representative_id=?,latest_id=?,lowest_tier_id=?,selection_revision=?,updated_at=CURRENT_TIMESTAMP(3) WHERE user_id=? AND song_id=? AND selection_revision=?",
                value(selected.representative()),value(selected.latest()),value(selected.lowestTier()),next,bytes(owner),bytes(song),previous.revision());
            if(changed!=1)throw new IllegalStateException("Selection revision changed");
            return Optional.of(new Snapshot(selected,next));
    }
    private record Song(UUID representative,boolean active) {}
    private boolean active(UUID owner) {
        return !jdbc.queryForList("SELECT id FROM app_user WHERE id=? AND status='ACTIVE'",bytes(owner)).isEmpty();
    }
    private static UUID id(byte[] value){return value==null?null:uuid(value);}
    private static byte[] value(UUID id){return id==null?null:bytes(id);}
    public record Snapshot(RetentionRoles.Ids ids,long revision) {
        public Set<UUID> recordingIds(){return ids.recordingIds();}
    }
}
