package com.ksh321.songrecord.api.uploads;

import com.ksh321.songrecord.api.retention.RetentionAssetVersions;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Called under the account mutation lock. Only approvals valid before detachment survive. */
public final class OrphanUploads {
    private OrphanUploads() {}
    public static void preserve(JdbcTemplate db, UUID owner, Collection<UUID> targets, Clock clock) {
        if(!org.springframework.transaction.support.TransactionSynchronizationManager.hasResource(db.getDataSource()))throw new IllegalStateException("Account mutation transaction required");
        com.ksh321.songrecord.api.locking.LockOrder.before(com.ksh321.songrecord.api.locking.LockOrder.Rank.USER_SYNC,owner.toString());
        db.queryForMap("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));
        var approved=new HashMap<UUID,UUID>();
        for(UUID recording:targets){
            var rows=db.queryForList("SELECT u.id FROM recording_upload u LEFT JOIN recording_asset a ON a.user_id=u.user_id AND a.recording_id=u.recording_id WHERE u.user_id=? AND u.recording_id=? AND u.state IN ('RESERVED','UPLOADING','VERIFYING') AND u.expires_at>? AND u.policy_revision=COALESCE(a.cloud_revision,1)",bytes(owner),bytes(recording),java.sql.Timestamp.from(clock.instant()));
            if(rows.size()>1)throw new IllegalStateException("Multiple active upload approvals");
            if(!rows.isEmpty())approved.put(recording,uuid((byte[])rows.getFirst().get("id")));
        }
        RetentionAssetVersions.bump(db,owner,targets);
        for(UUID recording:targets){
            UUID attempt=approved.get(recording);
            if(attempt!=null){
                var revisions=db.queryForList("SELECT cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=?",bytes(owner),bytes(recording));
                long revision=revisions.isEmpty()?1:((Number)revisions.getFirst().get("cloud_revision")).longValue();
                if(db.update("UPDATE recording_upload SET policy_revision=?,updated_at=? WHERE user_id=? AND id=? AND state IN ('RESERVED','UPLOADING','VERIFYING')",revision,java.sql.Timestamp.from(clock.instant()),bytes(owner),bytes(attempt))!=1)throw new IllegalStateException("Upload approval changed during detachment");
            }
            boolean stored=!db.queryForList("SELECT recording_id FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='STORED'",bytes(owner),bytes(recording)).isEmpty();
            if((stored || attempt!=null) && db.queryForList("SELECT id FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason='ORPHAN_KEEP'",bytes(owner),bytes(recording)).isEmpty())
                db.update("INSERT INTO cloud_hold(id,user_id,recording_id,reason) VALUES(?,?,?,'ORPHAN_KEEP')",bytes(UUID.randomUUID()),bytes(owner),bytes(recording));
        }
    }
}
