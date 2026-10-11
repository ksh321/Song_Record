package com.ksh321.songrecord.api.playlists;

import com.ksh321.songrecord.api.jobs.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Removes only committed deleted playlist bodies; tombstones and personal music remain. */
public final class PlaylistCleanup {
    private final JobRunner runner;private final JdbcTemplate jdbc;
    public PlaylistCleanup(JobRunner runner,JdbcTemplate jdbc){this.runner=runner;this.jdbc=jdbc;}
    public boolean runOnce(){return runner.runOnce(JobQueue.Type.PLAYLIST_CLEANUP,lease->()->{
        if(lease.userId()==null)throw new IllegalStateException("Playlist cleanup requires an owner");
        var owner=bytes(lease.userId());var id=bytes(lease.aggregateId());
        if(jdbc.queryForList("SELECT entity_id FROM deletion_ledger WHERE user_id=? AND entity_type='PLAYLIST' AND entity_id=? AND object_generation IS NULL",owner,id).isEmpty())throw new IllegalStateException("Playlist deletion proof missing");
        jdbc.update("DELETE FROM playlist_item WHERE user_id=? AND playlist_id=? AND EXISTS(SELECT 1 FROM playlist WHERE user_id=? AND id=? AND deleted_at IS NOT NULL)",owner,id,owner,id);
        jdbc.update("DELETE FROM playlist WHERE user_id=? AND id=? AND deleted_at IS NOT NULL",owner,id);
    });}
}
