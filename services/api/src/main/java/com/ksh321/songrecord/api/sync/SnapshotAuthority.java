package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.jobs.JobQueue;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Package-private server authority. Jobs carry lease IDs, never user login tokens. */
final class SnapshotAuthority {
    private final Supplier<UUID> validate;
    private final Runnable fence;
    private final UUID snapshot;
    private SnapshotAuthority(Supplier<UUID> validate,Runnable fence,UUID snapshot) {
        this.validate=validate;this.fence=fence;this.snapshot=snapshot;
    }
    static SnapshotAuthority request(AccountAccess access,AccountAccess.Account account) {
        return new SnapshotAuthority(()->access.revalidate(account).userId(),()->{},null);
    }
    static SnapshotAuthority job(JdbcTemplate jdbc,JobQueue.Lease lease,Clock clock) {
        Objects.requireNonNull(jdbc);Objects.requireNonNull(lease);Objects.requireNonNull(clock);
        if(lease.type()!=JobQueue.Type.SNAPSHOT_BUILD||lease.userId()==null)throw denied();
        Supplier<UUID> validate=()->{
            var rows=jdbc.query("SELECT j.user_id FROM job j JOIN app_user u ON u.id=j.user_id JOIN snapshot_header h ON h.id=j.aggregate_id AND h.user_id=j.user_id WHERE j.id=? AND j.lease_token=? AND j.state='RUNNING' AND j.type='SNAPSHOT_BUILD' AND j.lease_until>? AND u.status='ACTIVE' AND h.purpose='SYNC' AND j.user_id=? AND j.aggregate_id=?",
                    (rs,n)->uuid(rs.getBytes(1)),bytes(lease.id()),bytes(lease.token()),utc(clock.instant()),bytes(lease.userId()),bytes(lease.aggregateId()));
            if(rows.size()!=1)throw denied();return rows.getFirst();
        };
        Runnable fence=()->{
            if(!TransactionSynchronizationManager.isActualTransactionActive()
                    ||!TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))
                throw new IllegalStateException("Snapshot worker fence requires its database transaction");
            var rows=jdbc.query("SELECT id FROM job WHERE id=? AND lease_token=? AND state='RUNNING' AND type='SNAPSHOT_BUILD' AND user_id=? AND aggregate_id=? AND lease_until>? FOR UPDATE",
                    (rs,n)->1,bytes(lease.id()),bytes(lease.token()),bytes(lease.userId()),bytes(lease.aggregateId()),utc(clock.instant()));
            if(rows.size()!=1)throw denied();
            validate.get();
        };
        return new SnapshotAuthority(validate,fence,lease.aggregateId());
    }
    UUID requireActive(){return validate.get();}
    void requireSnapshot(UUID id){if(snapshot!=null&&!snapshot.equals(id))throw denied();}
    boolean isJob(){return snapshot!=null;}
    void fence(){fence.run();}
    private static IllegalStateException denied(){return new IllegalStateException("Snapshot worker authority expired or unavailable");}
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes){var b=ByteBuffer.wrap(bytes);return new UUID(b.getLong(),b.getLong());}
    private static LocalDateTime utc(Instant time){return LocalDateTime.ofInstant(time,ZoneOffset.UTC);}
    @Override public String toString(){return "SnapshotAuthority[REDACTED]";}
}
