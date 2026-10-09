package com.ksh321.songrecord.api.uploads;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.locking.*;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Database-only reservation primitive; HTTP eligibility/limits are connected by P12-03. */
public final class UploadReservations {
    private final JdbcTemplate db; private final AccountAccess access;
    private final TransactionTemplate tx; private final StorageLocks locks; private final Clock clock;
    public UploadReservations(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,Clock clock){
        this.db=db;this.access=access;this.clock=clock;tx=new TransactionTemplate(manager);tx.setIsolationLevel(org.springframework.transaction.TransactionDefinition.ISOLATION_READ_COMMITTED);locks=new StorageLocks(db,access,manager);
    }
    /** May join the command/receipt transaction. All upload policy checks execute inside these locks. */
    public <T>T locked(AccountAccess.Account account,Supplier<T> work){
        return tx.execute(status->{
            UUID owner=access.revalidate(account).userId();locks.global();
            LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());
            if(db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner)).size()!=1)throw new IllegalStateException("Account state missing");
            access.revalidate(account);locks.owned(account,StorageLocks.Target.ENTITLEMENT,null);locks.owned(account,StorageLocks.Target.USAGE,null);
            return work.get();
        });
    }
    public record Request(UUID recording,long size,String sha256,long policyRevision,UUID pinOperation){
        public Request(UUID recording,long size,String sha256,long policyRevision){this(recording,size,sha256,policyRevision,null);}
        public Request{Objects.requireNonNull(recording);if(size<1 || size>6291456 || sha256==null || !sha256.matches("[0-9a-f]{64}") || policyRevision<1)throw new IllegalArgumentException("Invalid upload reservation");}
    }
    public record Reservation(UUID attempt,UUID recording,long size,String state,Instant expiresAt) {}
    public Reservation reserve(AccountAccess.Account account,Request request){
        Objects.requireNonNull(request);
        return locked(account,()->{
            UUID owner=access.revalidate(account).userId();
            if(db.queryForList("SELECT id FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(request.recording())).isEmpty())throw error("RESOURCE_NOT_FOUND",HttpStatus.NOT_FOUND);
            var existing=db.query("SELECT id,recording_id,expected_size,state,expires_at FROM recording_upload WHERE user_id=? AND recording_id=? AND state IN ('RESERVED','UPLOADING','VERIFYING') FOR UPDATE",(r,n)->new Reservation(id(r.getBytes(1)),id(r.getBytes(2)),r.getLong(3),r.getString(4),r.getTimestamp(5).toInstant()),bytes(owner),bytes(request.recording()));
            if(!existing.isEmpty())return existing.getFirst();
            var global=db.queryForMap("SELECT used_bytes,reserved_bytes,primary_quota_bytes,upload_locked,temp_observed_bytes,reconciliation_locked,revision FROM global_storage_usage WHERE id=1 FOR UPDATE");
            var personal=db.queryForMap("SELECT s.used_bytes,s.reserved_bytes,s.revision,e.quota_bytes FROM storage_usage s JOIN user_entitlement e ON e.user_id=s.user_id WHERE s.user_id=? FOR UPDATE",bytes(owner));
            if(number(global,"temp_observed_bytes")>=536870912 || Boolean.TRUE.equals(global.get("reconciliation_locked")) || (global.get("reconciliation_locked") instanceof Number flag && flag.intValue()!=0))throw error("UPLOAD_BUDGET_LOCKED",HttpStatus.SERVICE_UNAVAILABLE);
            if(Boolean.TRUE.equals(global.get("upload_locked")) || (global.get("upload_locked") instanceof Number n && n.intValue()!=0))throw error("UPLOAD_BUDGET_LOCKED",HttpStatus.SERVICE_UNAVAILABLE);
            if(!fits(number(personal,"used_bytes"),number(personal,"reserved_bytes"),request.size(),number(personal,"quota_bytes"))
                || !fits(number(global,"used_bytes"),number(global,"reserved_bytes"),request.size(),number(global,"primary_quota_bytes")))throw error("QUOTA_EXCEEDED",HttpStatus.CONFLICT);
            var slots=db.query("SELECT active_slot FROM recording_upload WHERE user_id=? AND state IN ('RESERVED','UPLOADING','VERIFYING') FOR UPDATE",(r,n)->r.getInt(1),bytes(owner));
            int slot=!slots.contains(0)?0:!slots.contains(1)?1:-1;if(slot<0)throw error("UPLOAD_CONCURRENCY_LIMIT",HttpStatus.CONFLICT);
            long personalRevision=Math.incrementExact(number(personal,"revision")),globalRevision=Math.incrementExact(number(global,"revision"));
            UUID attempt=UUID.randomUUID();Instant now=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MILLIS),expiry=now.plus(Duration.ofHours(24));
            db.update("INSERT INTO recording_upload(id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,temp_key,final_key,policy_revision,pin_operation_id,expires_at,created_at,updated_at) VALUES(?,?,?,'RESERVED',?,?,?,?,?,?,?,?,?,?)",
                bytes(attempt),bytes(owner),bytes(request.recording()),slot,request.size(),request.sha256(),new StorageObjectKeys.Temporary(owner,request.recording(),attempt).value(),new StorageObjectKeys.Final(owner,request.recording(),UUID.randomUUID()).value(),request.policyRevision(),request.pinOperation()==null?null:bytes(request.pinOperation()),java.sql.Timestamp.from(expiry),java.sql.Timestamp.from(now),java.sql.Timestamp.from(now));
            db.update("UPDATE storage_usage SET reserved_bytes=?,revision=?,updated_at=? WHERE user_id=?",number(personal,"reserved_bytes")+request.size(),personalRevision,java.sql.Timestamp.from(now),bytes(owner));
            db.update("UPDATE global_storage_usage SET reserved_bytes=?,revision=?,updated_at=? WHERE id=1",number(global,"reserved_bytes")+request.size(),globalRevision,java.sql.Timestamp.from(now));
            return new Reservation(attempt,request.recording(),request.size(),"RESERVED",expiry);
        });
    }
    static boolean fits(long used,long reserved,long size,long quota){return used>=0 && reserved>=0 && size>0 && quota>=0 && used<=quota && reserved<=quota-used && size<=quota-used-reserved;}
    private static long number(Map<String,Object> row,String key){return ((Number)row.get(key)).longValue();}
    private static UUID id(byte[] b){var n=java.nio.ByteBuffer.wrap(b);return new UUID(n.getLong(),n.getLong());}
    private static ApiException error(String code,HttpStatus status){return new ApiException(status,code,"파일 업로드 예약 조건을 확인해 주세요.",false,Map.of());}
}
