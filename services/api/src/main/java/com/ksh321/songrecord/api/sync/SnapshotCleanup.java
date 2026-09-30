package com.ksh321.songrecord.api.sync;

import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;

/** Server-owned cleanup of derived snapshots only; mutation receipts and source data remain. */
public final class SnapshotCleanup {
    private record Candidate(UUID id,UUID owner,String status) {}
    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;
    private final Clock clock;
    public SnapshotCleanup(JdbcTemplate jdbc,PlatformTransactionManager manager,Clock clock) {
        this.jdbc=jdbc;this.clock=clock;transaction=new TransactionTemplate(manager);
        transaction.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);transaction.setTimeout(30);
    }
    public int runOnce() {
        return transaction.execute(tx->{
            jdbc.queryForObject("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1 FOR UPDATE",Long.class);
            var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC);
            var candidates=jdbc.query("""
                SELECT h.id,h.user_id,h.status FROM snapshot_header h
                LEFT JOIN app_user u ON u.id=h.user_id
                WHERE u.status='DELETING' OR h.status IN ('EXPIRED','FAILED')
                  OR (h.status='READY' AND h.expires_at<=?)
                  OR (h.status='BUILDING' AND h.lease_until<=? AND NOT EXISTS(
                    SELECT 1 FROM job j WHERE j.aggregate_id=h.id AND j.user_id=h.user_id
                      AND j.type='SNAPSHOT_BUILD' AND j.state IN ('QUEUED','RUNNING','RETRY_WAIT')))
                ORDER BY h.id LIMIT 100 FOR UPDATE
                """,(rs,n)->new Candidate(uuid(rs.getBytes(1)),uuid(rs.getBytes(2)),rs.getString(3)),now,now);
            for(var candidate:candidates) {
                if(candidate.status.equals("READY"))
                    jdbc.update("UPDATE snapshot_header SET status='EXPIRED',active_slot=NULL WHERE id=?",bytes(candidate.id));
                else if(candidate.status.equals("BUILDING"))
                    jdbc.update("UPDATE snapshot_header SET status='FAILED',active_slot=NULL,lease_until=NULL WHERE id=?",bytes(candidate.id));
                jdbc.update("UPDATE job SET state='CANCELLED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,finished_at=?,updated_at=?,revision=revision+1 WHERE user_id=? AND aggregate_id=? AND type='SNAPSHOT_BUILD' AND state IN ('QUEUED','RUNNING','RETRY_WAIT')",
                        now,now,bytes(candidate.owner),bytes(candidate.id));
                // V7 trigger refunds exactly the retained reservation. FK cascade
                // removes only snapshot_entry/export_session, never domain rows.
                jdbc.update("DELETE FROM snapshot_header WHERE id=? AND status IN ('EXPIRED','FAILED')",bytes(candidate.id));
            }
            return candidates.size();
        });
    }
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes){var b=ByteBuffer.wrap(bytes);return new UUID(b.getLong(),b.getLong());}
}
