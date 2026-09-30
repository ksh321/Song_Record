package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.CanonicalRequest;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.security.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** D09 durable BUILDING state. All mutations acquire capacity before header locks. */
public final class SnapshotBuildStore {
    public static final long MAX_BYTES=100L*1024*1024, GLOBAL_BYTES=1024L*1024*1024;
    public record Attempt(UUID id, UUID attemptId, Instant startedAt, String status) {
        @Override public String toString(){return "SnapshotAttempt[REDACTED]";}
    }
    public record Entry(SnapshotPages.Entity entity,long ordinal,UUID resourceId,String payload) {
        public Entry {
            Objects.requireNonNull(entity);Objects.requireNonNull(resourceId);
            if(ordinal<1)throw new IllegalArgumentException("Invalid snapshot ordinal");
            payload=CanonicalRequest.canonical(payload);
            if(!new JsonMapper().readTree(payload).isObject())throw new IllegalArgumentException("Expected object payload");
        }
        @Override public String toString(){return "SnapshotBuildEntry[REDACTED]";}
    }
    public record Published(UUID id,long cursor,Instant readyAt,Instant expiresAt,String manifestHash) {
        @Override public String toString(){return "SnapshotPublished[REDACTED]";}
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate transaction;
    private final Clock clock;
    public SnapshotBuildStore(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager,Clock clock) {
        this.jdbc=Objects.requireNonNull(jdbc);this.access=Objects.requireNonNull(access);this.clock=Objects.requireNonNull(clock);
        transaction=new TransactionTemplate(manager);
        transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        transaction.setTimeout(30);
    }
    public Attempt begin(AccountAccess.Account account,UUID opId,int schemaVersion) {
        Objects.requireNonNull(opId);
        if(schemaVersion!=1)throw error(HttpStatus.BAD_REQUEST,"SNAPSHOT_SCHEMA_UNSUPPORTED");
        return transaction.execute(tx->{
            UUID owner=access.revalidate(account).userId();capacity();
            var existing=jdbc.query("SELECT id,attempt_id,build_started_at,status,purpose,schema_version FROM snapshot_header WHERE user_id=? AND op_id=? FOR UPDATE",
                    (rs,n)->{
                        if(!rs.getString(5).equals("SYNC")||rs.getInt(6)!=schemaVersion)
                            throw error(HttpStatus.CONFLICT,"IDEMPOTENCY_CONFLICT");
                        return new Attempt(uuid(rs.getBytes(1)),uuid(rs.getBytes(2)),rs.getTimestamp(3).toLocalDateTime().toInstant(ZoneOffset.UTC),rs.getString(4));
                    },bytes(owner),bytes(opId));
            if(!existing.isEmpty())return existing.getFirst();
            var slots=jdbc.query("SELECT active_slot FROM snapshot_header WHERE user_id=? AND active_slot IS NOT NULL FOR UPDATE",
                    (rs,n)->rs.getInt(1),bytes(owner));
            if(slots.size()>=2)throw capacityExceeded();
            int slot=slots.contains(0)?1:0;
            UUID id=UUID.randomUUID(),attempt=UUID.randomUUID();Instant now=now();
            jdbc.update("INSERT INTO snapshot_header(id,user_id,op_id,purpose,schema_version,active_slot,reserved_bytes,attempt_id,build_started_at,lease_until,created_at) VALUES(?,?,?,'SYNC',?,?,0,?,?,?,?)",
                    bytes(id),bytes(owner),bytes(opId),schemaVersion,slot,bytes(attempt),utc(now),utc(now.plusSeconds(600)),utc(now));
            return new Attempt(id,attempt,now,"BUILDING");
        });
    }
    public void capture(AccountAccess.Account account,Attempt attempt,long cursor,Instant capturedAt) {
        Objects.requireNonNull(capturedAt);
        if(cursor<0)throw new IllegalArgumentException("Invalid snapshot baseline");
        transaction.executeWithoutResult(tx->{
            UUID owner=access.revalidate(account).userId();capacity();building(owner,attempt);
            if(capturedAt.isBefore(attempt.startedAt)||capturedAt.isAfter(now()))throw new IllegalArgumentException("Invalid capture time");
            int updated=jdbc.update("UPDATE snapshot_header SET snapshot_cursor=?,captured_at=? WHERE id=? AND snapshot_cursor IS NULL AND captured_at IS NULL",
                    cursor,utc(capturedAt),bytes(attempt.id));
            if(updated!=1)throw error(HttpStatus.CONFLICT,"SNAPSHOT_CAPTURE_ALREADY_SET");
        });
    }
    public void append(AccountAccess.Account account,Attempt attempt,List<Entry> batch) {
        var entries=List.copyOf(batch);
        if(entries.isEmpty()||entries.size()>100)throw new IllegalArgumentException("Expected 1..100 snapshot rows");
        transaction.executeWithoutResult(tx->{
            UUID owner=access.revalidate(account).userId();long global=capacity();long reserved=building(owner,attempt);
            Long cursor=jdbc.queryForObject("SELECT snapshot_cursor FROM snapshot_header WHERE id=?",Long.class,bytes(attempt.id));
            if(cursor==null)throw error(HttpStatus.CONFLICT,"SNAPSHOT_CAPTURE_REQUIRED");
            long bytes=0;
            for(var entry:entries) {
                Long size=jdbc.queryForObject("SELECT OCTET_LENGTH(CAST(CAST(? AS JSON) AS CHAR CHARACTER SET utf8mb4))",Long.class,entry.payload);
                bytes=Math.addExact(bytes,Objects.requireNonNull(size));
            }
            if(bytes>MAX_BYTES-reserved||bytes>GLOBAL_BYTES-global)throw capacityExceeded();
            jdbc.update("UPDATE snapshot_header SET reserved_bytes=? WHERE id=?",reserved+bytes,bytes(attempt.id));
            for(var entry:entries)jdbc.update("INSERT INTO snapshot_entry(snapshot_id,attempt_id,entity,ordinal,resource_id,payload) VALUES(?,?,?,?,?,?)",
                    bytes(attempt.id),bytes(attempt.attemptId),entry.entity.name(),entry.ordinal,bytes(entry.resourceId),entry.payload);
        });
    }
    /** expectedCounts must be produced after all entities finish in the same source read view. */
    public Published publish(AccountAccess.Account account,Attempt attempt,Map<SnapshotPages.Entity,Long> expectedCounts) {
        var expected=Map.copyOf(expectedCounts);
        if(!expected.keySet().equals(EnumSet.allOf(SnapshotPages.Entity.class))||expected.values().stream().anyMatch(n->n<0))
            throw new IllegalArgumentException("A complete entity manifest is required");
        return transaction.execute(tx->{
            UUID owner=access.revalidate(account).userId();capacity();building(owner,attempt);
            Long cursor=jdbc.queryForObject("SELECT snapshot_cursor FROM snapshot_header WHERE id=?",Long.class,bytes(attempt.id));
            if(cursor==null)throw error(HttpStatus.CONFLICT,"SNAPSHOT_CAPTURE_REQUIRED");
            var counts=new EnumMap<SnapshotPages.Entity,Long>(SnapshotPages.Entity.class);
            for(var entity:SnapshotPages.Entity.values())counts.put(entity,0L);
            MessageDigest digest;
            try{digest=MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}
            // Hash a versioned length-prefixed contract, independent of MySQL JSON whitespace.
            digest.update("SongRecord:snapshot-manifest:1".getBytes(StandardCharsets.US_ASCII));
            digest.update(ByteBuffer.allocate(8).putLong(cursor).array());
            jdbc.query("SELECT entity,ordinal,resource_id,payload FROM snapshot_entry WHERE snapshot_id=? ORDER BY entity,ordinal",
                    (org.springframework.jdbc.core.RowCallbackHandler)rs->{
                        var entity=SnapshotPages.Entity.valueOf(rs.getString(1));
                        long ordinal=rs.getLong(2),next=counts.get(entity)+1;
                        if(ordinal!=next)throw error(HttpStatus.CONFLICT,"SNAPSHOT_INCOMPLETE");
                        counts.put(entity,next);
                        byte[] name=entity.name().getBytes(StandardCharsets.US_ASCII);
                        byte[] payload=CanonicalRequest.canonical(rs.getString(4)).getBytes(StandardCharsets.UTF_8);
                        digest.update(ByteBuffer.allocate(4).putInt(name.length).array());digest.update(name);
                        digest.update(ByteBuffer.allocate(8).putLong(ordinal).array());digest.update(rs.getBytes(3));
                        digest.update(ByteBuffer.allocate(4).putInt(payload.length).array());digest.update(payload);
                    },bytes(attempt.id));
            if(!counts.equals(expected))throw error(HttpStatus.CONFLICT,"SNAPSHOT_INCOMPLETE");
            if(!access.revalidate(account).userId().equals(owner))throw error(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION");
            building(owner,attempt);
            Instant ready=now(),expiry=ready.plusSeconds(1800);
            String hash=HexFormat.of().formatHex(digest.digest());
            jdbc.update("UPDATE snapshot_header SET status='READY',ready_at=?,expires_at=?,manifest_hash=?,lease_until=NULL WHERE id=?",
                    utc(ready),utc(expiry),hash,bytes(attempt.id));
            return new Published(attempt.id,cursor,ready,expiry,hash);
        });
    }
    private long capacity() {
        var values=jdbc.query("SELECT reserved_bytes FROM snapshot_capacity WHERE id=1 FOR UPDATE",(rs,n)->rs.getLong(1));
        if(values.size()!=1)throw new IllegalStateException("Missing snapshot capacity ledger");
        return values.getFirst();
    }
    private long building(UUID owner,Attempt attempt) {
        Objects.requireNonNull(attempt);
        var rows=jdbc.query("SELECT attempt_id,status,reserved_bytes,build_started_at,lease_until FROM snapshot_header WHERE user_id=? AND id=? AND purpose='SYNC' FOR UPDATE",
                (rs,n)->{
                    Instant start=rs.getTimestamp(4).toLocalDateTime().toInstant(ZoneOffset.UTC);
                    var lease=rs.getTimestamp(5);
                    if(!uuid(rs.getBytes(1)).equals(attempt.attemptId)||!start.equals(attempt.startedAt)||now().isBefore(start)||!rs.getString(2).equals("BUILDING")
                            ||lease==null||!now().isBefore(lease.toLocalDateTime().toInstant(ZoneOffset.UTC)))
                        throw error(HttpStatus.CONFLICT,"SNAPSHOT_ATTEMPT_STALE");
                    return rs.getLong(3);
                },bytes(owner),bytes(attempt.id));
        if(rows.isEmpty())throw error(HttpStatus.NOT_FOUND,"SNAPSHOT_NOT_FOUND");
        return rows.getFirst();
    }
    private Instant now(){return clock.instant().truncatedTo(ChronoUnit.MILLIS);}
    private static LocalDateTime utc(Instant instant){return LocalDateTime.ofInstant(instant,ZoneOffset.UTC);}
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes){var b=ByteBuffer.wrap(bytes);return new UUID(b.getLong(),b.getLong());}
    private static ApiException capacityExceeded(){return error(HttpStatus.TOO_MANY_REQUESTS,"SNAPSHOT_CAPACITY_EXCEEDED");}
    private static ApiException error(HttpStatus status,String code){return new ApiException(status,code,"스냅샷 생성 상태를 확인해 주세요.",false,Map.of());}
}
