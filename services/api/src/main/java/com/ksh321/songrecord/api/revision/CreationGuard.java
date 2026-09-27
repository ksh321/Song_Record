package com.ksh321.songrecord.api.revision;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;

/** UUID safety after receipt retention. Domain creation/deletion must share the account sync lock. */
public final class CreationGuard {
    public enum Resource {
        SONG("song", "lifecycle_state"), RECORDING("recording", "lifecycle_state"),
        PLAYLIST("playlist", "CASE WHEN deleted_at IS NULL THEN 'ACTIVE' ELSE 'DELETED' END"),
        TAG("tag", "CASE WHEN archived_at IS NULL THEN 'ACTIVE' ELSE 'ARCHIVED' END");
        final String table, state;
        Resource(String table, String state) { this.table=table; this.state=state; }
    }
    public record Existing(long revision, String state) {}
    public record Result<T>(boolean created, T value, Existing existing) {
        @Override public String toString() { return "CreationResult[created="+created+", data=REDACTED]"; }
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate joined;
    public CreationGuard(JdbcTemplate jdbc, AccountAccess access, PlatformTransactionManager manager) {
        this.jdbc=jdbc;this.access=access;joined=new TransactionTemplate(manager);
        joined.setPropagationBehavior(TransactionDefinition.PROPAGATION_MANDATORY);
    }
    /** Invoke after receipt reservation and optional global capacity lock, before any domain locks. */
    public <T> Result<T> create(AccountAccess.Account account, Resource resource, UUID id, Supplier<T> insert) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()
                || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))
            throw new IllegalStateException("Creation guard requires the mutation database transaction");
        Objects.requireNonNull(resource);Objects.requireNonNull(id);Objects.requireNonNull(insert);
        return joined.execute(status->{
            var owner=access.revalidate(account).userId();
            LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());
            if(jdbc.query("SELECT last_change_seq FROM user_sync_state WHERE user_id=? FOR UPDATE",(rs,n)->rs.getLong(1),bytes(owner)).size()!=1)
                throw new IllegalStateException("Account sync state is missing");
            // Current locking read remains safe even if an enclosing repeatable-read view predates the purge.
            LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/"+resource.ordinal()+"/"+id);
            if(!jdbc.query("SELECT revision FROM deletion_ledger WHERE user_id=? AND entity_type=? AND entity_id=? AND object_generation IS NULL FOR UPDATE",
                    (rs,n)->rs.getLong(1),bytes(owner),resource.name(),bytes(id)).isEmpty()) throw purged();
            var rows=jdbc.query("SELECT revision,"+resource.state+" AS current_state FROM "+resource.table+" WHERE user_id=? AND id=? FOR UPDATE",
                    (rs,n)->new Existing(rs.getLong(1),rs.getString(2)),bytes(owner),bytes(id));
            if(!rows.isEmpty()) return new Result<T>(false,null,rows.getFirst());
            return new Result<T>(true,Objects.requireNonNull(insert.get()),null);
        });
    }
    private static byte[] bytes(UUID id) { return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array(); }
    private static ApiException purged() { return new ApiException(HttpStatus.CONFLICT,"RESOURCE_PURGED","영구 삭제된 자료는 같은 ID로 다시 만들 수 없습니다.",false,Map.of()); }
}
