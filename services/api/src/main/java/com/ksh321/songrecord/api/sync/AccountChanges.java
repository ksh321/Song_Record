package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.idempotency.CanonicalRequest;
import java.nio.ByteBuffer;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;
import tools.jackson.databind.json.JsonMapper;

/** Serializes each account's domain writes and change records until the surrounding commit. */
public final class AccountChanges {
    public enum Entity { SONG, RECORDING, PLAYLIST, PLAYLIST_ITEM, TAG, RECORDING_ASSET, CONDITION }
    public enum Operation { UPSERT, DELETE }
    public record Change(Entity entity, UUID id, long revision, Operation operation, String payload) {
        public Change {
            Objects.requireNonNull(entity);Objects.requireNonNull(id);Objects.requireNonNull(operation);
            if(revision<1)throw new IllegalArgumentException("Revision must be positive");
            payload=CanonicalRequest.canonical(payload);
            if(!new JsonMapper().readTree(payload).isObject())throw new IllegalArgumentException("Change payload must be an object");
        }
        @Override public String toString(){return "Change[REDACTED]";}
    }
    public record Batch<T>(T value,List<Change> changes) {
        public Batch {changes=List.copyOf(changes);if(changes.isEmpty())throw new IllegalArgumentException("A write must record a change");}
        @Override public String toString(){return "Batch[REDACTED]";}
    }
    public record Recorded<T>(T value,long lastChangeSeq) {
        @Override public String toString(){return "Recorded[lastChangeSeq="+lastChangeSeq+", value=REDACTED]";}
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate joined;
    private final Clock clock;
    private final com.ksh321.songrecord.api.jobs.JobQueue retentionJobs;
    public AccountChanges(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager,Clock clock) {
        this.jdbc=jdbc;this.access=access;this.clock=clock;
        retentionJobs=new com.ksh321.songrecord.api.jobs.JobQueue(jdbc,access,manager,clock,java.time.Duration.ofMinutes(2),5);
        joined=new TransactionTemplate(manager);joined.setPropagationBehavior(TransactionDefinition.PROPAGATION_MANDATORY);
    }
    /** Call after any required global lock, but BEFORE all account/domain row locks and edits. */
    public <T> Recorded<T> write(AccountAccess.Account account,Supplier<Batch<T>> edit) {
        if(!TransactionSynchronizationManager.isActualTransactionActive()
                || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))
            throw new IllegalStateException("Change tracking requires the mutation database transaction");
        return joined.execute(status->{
            var owner=access.revalidate(account);
            LockOrder.before(LockOrder.Rank.USER_SYNC,owner.userId().toString());
            var rows=jdbc.query("SELECT last_change_seq FROM user_sync_state WHERE user_id=? FOR UPDATE",
                    (rs,row)->rs.getLong(1),bytes(owner.userId()));
            if(rows.size()!=1)throw new IllegalStateException("Account sync state is missing");
            long sequence=rows.getFirst();
            if(sequence<0)throw new IllegalStateException("Invalid account sequence");
            com.ksh321.songrecord.api.retention.RetentionEvents.begin(owner.userId());
            Batch<T> batch;
            try {
                batch=Objects.requireNonNull(edit.get());
                com.ksh321.songrecord.api.retention.RetentionEvents.flush(retentionJobs,account);
            } finally {com.ksh321.songrecord.api.retention.RetentionEvents.end();}
            if(sequence>Long.MAX_VALUE-batch.changes().size())throw new IllegalStateException("Account sequence exhausted");
            var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);
            for(var change:batch.changes()) {
                jdbc.update("INSERT INTO change_log(user_id,change_seq,entity_type,entity_id,revision,operation,payload,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?)",
                        bytes(owner.userId()),++sequence,change.entity().name(),bytes(change.id()),change.revision(),
                        change.operation().name(),change.payload(),now,now.plusDays(90));
            }
            int updated=jdbc.update("UPDATE user_sync_state SET last_change_seq=?,updated_at=? WHERE user_id=? AND last_change_seq=?",
                    sequence,now,bytes(owner.userId()),rows.getFirst());
            if(updated!=1)throw new IllegalStateException("Edit modified the account sequence");
            return new Recorded<>(batch.value(),sequence);
        });
    }
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
