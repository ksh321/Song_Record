package com.ksh321.songrecord.api.uploads;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.retention.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.PlatformTransactionManager;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.uuid;

/** Approval policy. UploadUrls combines it with local signing in the receipt transaction. */
public final class UploadApproval {
    private final JdbcTemplate db; private final AccountAccess access;private final UploadReservations reservations;
    private final IdempotentMutations mutations;private final Clock clock;private final RetentionRoles roles;
    private static final JsonMapper JSON=new JsonMapper();
    public UploadApproval(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,Clock clock,IdempotentMutations mutations){
        this.db=db;this.access=access;this.clock=clock;this.mutations=mutations;reservations=new UploadReservations(db,access,manager,clock);roles=new RetentionRoles(new RetentionCandidates(db));
    }
    public IdempotentMutations.Reply authorize(String auth,String device,String operation,UUID recording,String body){
        return authorize(auth,device,operation,recording,body,(account,result)->Map.of());
    }
    public IdempotentMutations.Reply authorize(String auth,String device,String operation,UUID recording,String body,java.util.function.BiFunction<AccountAccess.Account,Approval,Map<String,Object>> issuance){
        var account=access.authenticate(auth,device);CanonicalRequest.canonical(body);var root=JSON.readTree(body);
        if(!root.isObject() || root.size()!=2 || !root.has("expected_size") || !root.has("sha256") || !root.get("expected_size").isIntegralNumber() || !root.get("expected_size").canConvertToLong() || !root.get("sha256").isTextual())throw error("INVALID_REQUEST",HttpStatus.BAD_REQUEST);
        long size=root.get("expected_size").asLong();String sha=root.get("sha256").asText();
        if(size<1 || size>6291456 || !sha.matches("[0-9a-f]{64}"))throw error("INVALID_REQUEST",HttpStatus.BAD_REQUEST);
        return mutations.execute(account,operation,"POST","/v1/recordings/"+Objects.requireNonNull(recording)+"/uploads",body,()->{
            var result=approve(account,recording,size,sha);
            var response=new LinkedHashMap<String,Object>();response.put("state",result.state());
            if(result.attempt()!=null){response.put("attempt_id",result.attempt().toString());response.put("expires_at",result.expiresAt().toString());}
            response.putAll(issuance.apply(account,result));
            return new IdempotentMutations.Reply(result.state().equals("STORED")?200:201,JSON.writeValueAsString(response));
        });
    }
    public record Approval(UUID attempt,String state,Instant expiresAt) {}
    public Approval approve(AccountAccess.Account account,UUID recording,long size,String sha){
        Objects.requireNonNull(recording);
        return reservations.locked(account,()->{
            if(!Integer.valueOf(org.springframework.transaction.TransactionDefinition.ISOLATION_READ_COMMITTED).equals(org.springframework.transaction.support.TransactionSynchronizationManager.getCurrentTransactionIsolationLevel()))throw new IllegalStateException("Upload approval requires current committed policy");
            UUID owner=access.revalidate(account).userId();
            var rows=db.queryForList("SELECT song_id,lifecycle_state,metadata_state FROM recording WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(recording));
            if(rows.isEmpty())throw error("RESOURCE_NOT_FOUND",HttpStatus.NOT_FOUND);var row=rows.getFirst();
            if(!"ACTIVE".equals(row.get("lifecycle_state")) || !"SAVED".equals(row.get("metadata_state")))throw error("NOT_CLOUD_TARGET",HttpStatus.CONFLICT);
            var specs=db.query("SELECT sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity FROM recording_file_spec WHERE user_id=? AND recording_id=?",(r,n)->new RetentionCandidates.FileSpec(r.getString(1),r.getLong(2),r.getInt(3),r.getString(4),r.getInt(5),r.getInt(6),r.getString(7)),bytes(owner),bytes(recording));
            if(specs.size()!=1 || !specs.getFirst().valid() || specs.getFirst().sizeBytes()!=size || !Objects.equals(specs.getFirst().sha256(),sha))throw error("FILE_SPEC_MISMATCH",HttpStatus.CONFLICT);
            boolean target=!db.queryForList("SELECT slot_no FROM pin_slot WHERE user_id=? AND (current_recording_id=? OR pending_recording_id=?)",bytes(owner),bytes(recording),bytes(recording)).isEmpty()
                || !db.queryForList("SELECT recording_id FROM cloud_hold WHERE user_id=? AND recording_id=?",bytes(owner),bytes(recording)).isEmpty();
            if(!target && row.get("song_id")!=null){
                UUID song=uuid((byte[])row.get("song_id"));
                target=roles.representative(owner,song).map(s->s.candidate().recordingId().equals(recording)).orElse(false)
                    || roles.latest(owner,song).map(s->s.candidate().recordingId().equals(recording)).orElse(false)
                    || roles.lowestTier(owner,song).map(s->s.candidate().recordingId().equals(recording)).orElse(false);
            }
            if(!target)throw error("NOT_CLOUD_TARGET",HttpStatus.CONFLICT);
            var assets=db.queryForList("SELECT cloud_state,cloud_revision,verified_size,sha256 FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(recording));
            if(!assets.isEmpty() && "STORED".equals(assets.getFirst().get("cloud_state"))){
                var asset=assets.getFirst();
                if(((Number)asset.get("verified_size")).longValue()!=size || !sha.equals(asset.get("sha256")))throw error("FILE_SPEC_MISMATCH",HttpStatus.CONFLICT);
                return new Approval(null,"STORED",null);
            }
            if(!assets.isEmpty() && "DELETING".equals(assets.getFirst().get("cloud_state")))throw error("FILE_CLEANUP_IN_PROGRESS",HttpStatus.CONFLICT);
            long policy=assets.isEmpty()?1:((Number)assets.getFirst().get("cloud_revision")).longValue();
            // Existing attempts allocate neither extra capacity nor daily/URL budget.
            boolean exists=!db.queryForList("SELECT id FROM recording_upload WHERE user_id=? AND recording_id=? AND state IN ('RESERVED','UPLOADING','VERIFYING')",bytes(owner),bytes(recording)).isEmpty();
            if(exists)return result(reservations.reserve(account,new UploadReservations.Request(recording,size,sha,policy)));
            LocalDate day=LocalDate.ofInstant(clock.instant(),ZoneOffset.UTC);
            var daily=db.query("SELECT approved_bytes FROM upload_approval_daily WHERE user_id=? AND utc_day=? FOR UPDATE",(r,n)->r.getLong(1),bytes(owner),java.sql.Date.valueOf(day));
            long used=daily.isEmpty()?0:daily.getFirst();if(used<0 || size>104857600-used)throw error("UPLOAD_DAILY_LIMIT",HttpStatus.TOO_MANY_REQUESTS);
            var pins=db.queryForList("SELECT operation_id FROM pin_slot WHERE user_id=? AND pending_recording_id=?",bytes(owner),bytes(recording));UUID pinOperation=pins.isEmpty() || pins.getFirst().get("operation_id")==null?null:uuid((byte[])pins.getFirst().get("operation_id"));
            var result=reservations.reserve(account,new UploadReservations.Request(recording,size,sha,policy,pinOperation));
            issuePermit(account);
            if(daily.isEmpty())db.update("INSERT INTO upload_approval_daily(user_id,utc_day,approved_bytes) VALUES(?,?,?)",bytes(owner),java.sql.Date.valueOf(day),size);
            else db.update("UPDATE upload_approval_daily SET approved_bytes=? WHERE user_id=? AND utc_day=?",used+size,bytes(owner),java.sql.Date.valueOf(day));
            return result(result);
        });
    }
    /** Shared issuance quota for initial/renewed URLs; caller must roll back if actual issuance fails. */
    public void issuePermit(AccountAccess.Account account){
        reservations.locked(account,()->{
            UUID owner=access.revalidate(account).userId();Instant now=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MILLIS),start=now.minusSeconds(60);
            db.update("DELETE FROM upload_url_issue WHERE user_id=? AND issued_at<=?",bytes(owner),java.sql.Timestamp.from(start));
            long count=db.queryForObject("SELECT COUNT(*) FROM upload_url_issue WHERE user_id=?",Long.class,bytes(owner));
            if(count>=10)throw error("UPLOAD_RATE_LIMITED",HttpStatus.TOO_MANY_REQUESTS);
            db.update("INSERT INTO upload_url_issue(user_id,id,issued_at) VALUES(?,?,?)",bytes(owner),bytes(UUID.randomUUID()),java.sql.Timestamp.from(now));return null;
        });
    }
    private static Approval result(UploadReservations.Reservation r){return new Approval(r.attempt(),r.state(),r.expiresAt());}
    private static ApiException error(String code,HttpStatus status){return new ApiException(status,code,"업로드 승인 조건을 확인해 주세요.",false,Map.of());}
}
