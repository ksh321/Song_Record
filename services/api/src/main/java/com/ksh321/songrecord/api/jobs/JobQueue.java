package com.ksh321.songrecord.api.jobs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.idempotency.CanonicalRequest;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;

/** Durable queue. Only trusted domain code calls this; no public job-submission endpoint. */
public final class JobQueue {
    public enum Type { UPLOAD_VERIFY, ASSET_DELETE, POLICY_RECALCULATE, BACKUP_RECONCILE, SNAPSHOT_BUILD }
    public record Lease(UUID id, UUID token, UUID userId, Type type, UUID aggregateId, String payload, int attempt) {
        @Override public String toString(){return "Lease[REDACTED]";}
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate tx, joined;
    private final Clock clock;
    private final Duration leaseDuration;
    private final int maxAttempts;
    public JobQueue(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager,Clock clock,Duration leaseDuration,int maxAttempts) {
        if(leaseDuration.compareTo(Duration.ofSeconds(1))<0 || leaseDuration.compareTo(Duration.ofHours(1))>0 || maxAttempts<1 || maxAttempts>100)throw new IllegalArgumentException("Invalid job policy");
        this.jdbc=jdbc;this.access=access;this.clock=clock;this.leaseDuration=leaseDuration;this.maxAttempts=maxAttempts;
        tx=new TransactionTemplate(manager);tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);tx.setTimeout(30);
        joined=new TransactionTemplate(manager);joined.setPropagationBehavior(TransactionDefinition.PROPAGATION_MANDATORY);
    }
    public UUID enqueue(AccountAccess.Account account,Type type,UUID aggregate,UUID operation,String payload) {
        requireTransaction();
        return joined.execute(s->insert(access.revalidate(account).userId(),type,aggregate,operation,payload));
    }
    public record Submission(Type type,UUID aggregate,UUID operation,String payload){
        public Submission {Objects.requireNonNull(type);Objects.requireNonNull(aggregate);Objects.requireNonNull(operation);Objects.requireNonNull(payload);}
        @Override public String toString(){return "JobSubmission[REDACTED]";}
    }
    /** Multiple jobs must acquire their dedupe locks in the same order as single inserts. */
    public List<UUID> enqueueAll(AccountAccess.Account account,List<Submission> requests){
        requireTransaction();var copy=List.copyOf(requests);
        return joined.execute(s->{
            UUID user=access.revalidate(account).userId();
            var ordered=copy.stream().sorted(Comparator.comparing(r->HexFormat.of().formatHex(dedupe(user,r.type(),r.aggregate(),r.operation())))).toList();
            var result=new ArrayList<UUID>();
            for(var r:ordered)result.add(insert(user,r.type(),r.aggregate(),r.operation(),r.payload()));
            return List.copyOf(result);
        });
    }
    private static byte[] dedupe(UUID user,Type type,UUID aggregate,UUID operation){return digest((user==null?"GLOBAL":user.toString())+"/"+type+"/"+aggregate+"/"+operation);}
    /** Reserved for server-owned maintenance; never take userId/type/payload from an untrusted request. */
    public UUID enqueueMaintenance(Type type,UUID aggregate,UUID operation,String payload) {
        requireTransaction();return joined.execute(s->insert(null,type,aggregate,operation,payload));
    }
    private UUID insert(UUID user,Type type,UUID aggregate,UUID operation,String payload) {
        Objects.requireNonNull(type);Objects.requireNonNull(aggregate);Objects.requireNonNull(operation);
        String canonical=CanonicalRequest.canonical(payload);
        if(!canonical.startsWith("{"))throw new IllegalArgumentException("Job payload must be an object");
        byte[] dedupe=dedupe(user,type,aggregate,operation);
        LockOrder.before(LockOrder.Rank.JOB,HexFormat.of().formatHex(dedupe));
        UUID id=UUID.randomUUID();var now=now();
        try {
            jdbc.update("INSERT INTO job(id,user_id,type,aggregate_id,dedupe_key,payload,state,attempt_count,run_after,revision,created_at,updated_at) VALUES(?,?,?,?,?,?,'QUEUED',0,?,1,?,?)",
                    bytes(id),bytes(user),type.name(),bytes(aggregate),dedupe,canonical,now,now,now);
            return id;
        } catch(DuplicateKeyException e) {
            var rows=jdbc.query("SELECT id,payload FROM job WHERE dedupe_key=? FOR UPDATE",(rs,n)->Map.entry(uuid(rs.getBytes(1)),rs.getString(2)),dedupe);
            if(rows.size()!=1)throw e;
            if(!canonical.equals(CanonicalRequest.canonical(rows.getFirst().getValue())))throw new IllegalArgumentException("Job dedupe key reused with different payload");
            return rows.getFirst().getKey();
        }
    }
    public Optional<Lease> claim(Type type) {
        requireBoundary();Objects.requireNonNull(type);
        return tx.execute(s->{
            var now=now();
            var rows=jdbc.query("SELECT id,user_id,aggregate_id,payload,attempt_count FROM job WHERE type=? AND ((state IN ('QUEUED','RETRY_WAIT') AND run_after<=?) OR (state='RUNNING' AND lease_until<=?)) ORDER BY run_after,id LIMIT 1 FOR UPDATE SKIP LOCKED",
                    (rs,n)->new Lease(uuid(rs.getBytes(1)),UUID.randomUUID(),uuid(rs.getBytes(2)),type,uuid(rs.getBytes(3)),rs.getString(4),rs.getInt(5)+1),type.name(),now,now);
            if(rows.isEmpty())return Optional.empty();
            var lease=rows.getFirst();
            LockOrder.before(LockOrder.Rank.JOB,lease.id().toString());
            if(lease.attempt()>maxAttempts) {
                jdbc.update("UPDATE job SET state='FAILED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,last_error='ATTEMPTS_EXHAUSTED',finished_at=?,updated_at=?,revision=revision+1 WHERE id=?",now,now,bytes(lease.id()));
                return Optional.empty();
            }
            jdbc.update("UPDATE job SET state='RUNNING',attempt_count=?,lease_token=?,claimed_at=?,lease_until=?,finished_at=NULL,updated_at=?,revision=revision+1 WHERE id=?",
                    lease.attempt(),bytes(lease.token()),now,now.plus(leaseDuration),now,bytes(lease.id()));
            return Optional.of(lease);
        });
    }
    public boolean renew(Lease lease) {
        requireBoundary();return Boolean.TRUE.equals(tx.execute(s->{LockOrder.before(LockOrder.Rank.JOB,lease.id().toString());var now=now();return jdbc.update("UPDATE job SET lease_until=?,updated_at=?,revision=revision+1 WHERE id=? AND state='RUNNING' AND lease_token=? AND lease_until>?",now.plus(leaseDuration),now,bytes(lease.id()),bytes(lease.token()),now)==1;}));
    }
    /** Apply transactional DB effects, then fence completion. A lease lost during effects rolls them back. */
    public boolean complete(Lease lease,Runnable databaseEffects) {
        requireBoundary();return Boolean.TRUE.equals(tx.execute(s->{
            // Initial read does not lock the job before lower-ranked domain rows.
            if(jdbc.query("SELECT id FROM job WHERE id=? AND state='RUNNING' AND lease_token=? AND lease_until>?",
                    (rs,n)->1,bytes(lease.id()),bytes(lease.token()),now()).isEmpty())return false;
            databaseEffects.run();
            LockOrder.before(LockOrder.Rank.JOB,lease.id().toString());
            var now=now();
            int updated=jdbc.update("UPDATE job SET state='SUCCEEDED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,last_error=NULL,finished_at=?,updated_at=?,revision=revision+1 WHERE id=? AND state='RUNNING' AND lease_token=? AND lease_until>?",now,now,bytes(lease.id()),bytes(lease.token()),now);
            if(updated!=1)throw new IllegalStateException("Job lease expired during completion");
            return true;
        }));
    }
    public boolean fail(Lease lease,boolean retryable) {
        requireBoundary();return Boolean.TRUE.equals(tx.execute(s->{
            if(!owns(lease))return false;
            var now=now();boolean retry=retryable && lease.attempt()<maxAttempts;
            long delay=Math.min(300,5L << Math.min(lease.attempt()-1,6));
            return jdbc.update("UPDATE job SET state=?,run_after=?,lease_token=NULL,claimed_at=NULL,lease_until=NULL,last_error=?,finished_at=?,updated_at=?,revision=revision+1 WHERE id=? AND lease_token=?",
                    retry?"RETRY_WAIT":"FAILED",now.plusSeconds(delay),retryable?"EXECUTION_FAILED":"PERMANENT_FAILURE",retry?null:now,now,bytes(lease.id()),bytes(lease.token()))==1;
        }));
    }
    private boolean owns(Lease lease) {
        LockOrder.before(LockOrder.Rank.JOB,lease.id().toString());
        return !jdbc.query("SELECT id FROM job WHERE id=? AND state='RUNNING' AND lease_token=? AND lease_until>? FOR UPDATE",(rs,n)->1,bytes(lease.id()),bytes(lease.token()),now()).isEmpty();
    }
    private void requireTransaction(){if(!TransactionSynchronizationManager.isActualTransactionActive() || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))throw new IllegalStateException("Enqueue requires the domain transaction");}
    private static void requireBoundary(){if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Worker requires an independent transaction boundary");}
    private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);}
    private static byte[] digest(String text){try{return MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));}catch(java.security.NoSuchAlgorithmException e){throw new IllegalStateException(e);}}
    private static byte[] bytes(UUID id){return id==null?null:ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] data){if(data==null)return null;var b=ByteBuffer.wrap(data);return new UUID(b.getLong(),b.getLong());}
}
