package com.ksh321.songrecord.api.uploads;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

public final class UploadUrls {
    private final JdbcTemplate db; private final AccountAccess access;
    private final UploadApproval approval; private final UploadReservations reservations;
    private final IdempotentMutations mutations; private final UploadPutSigner signer; private final Clock clock;
    private static final JsonMapper JSON=new JsonMapper();
    public UploadUrls(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,
        IdempotentMutations mutations,UploadApproval approval,UploadPutSigner signer,Clock clock){
        this.db=db;this.access=access;this.mutations=mutations;this.approval=approval;this.signer=signer;this.clock=clock;
        reservations=new UploadReservations(db,access,manager,clock);
    }
    public IdempotentMutations.Reply authorize(String auth,String device,String operation,UUID recording,String body){
        return approval.authorize(auth,device,operation,recording,body,(account,result)->
            result.attempt()==null?Map.of():issue(account,result.attempt(),false));
    }
    public IdempotentMutations.Reply renew(String auth,String device,String operation,UUID attempt){
        var account=access.authenticate(auth,device);
        return mutations.execute(account,operation,"POST","/v1/uploads/"+attempt+"/renew-url","{}",()->
            new IdempotentMutations.Reply(200,JSON.writeValueAsString(reservations.locked(account,()->issue(account,attempt,true)))));
    }
    private Map<String,Object> issue(AccountAccess.Account account,UUID attempt,boolean renew){
        UUID owner=access.revalidate(account).userId();
        var rows=db.query("SELECT recording_id,state,expires_at,expected_size,expected_sha256 FROM recording_upload WHERE user_id=? AND id=? FOR UPDATE",(rs,n)->Map.<String,Object>of("recording_id",rs.getBytes("recording_id"),"state",rs.getString("state"),"expires_at",rs.getTimestamp("expires_at").toInstant(),"expected_size",rs.getLong("expected_size"),"expected_sha256",rs.getString("expected_sha256")),bytes(owner),bytes(attempt));
        if(rows.isEmpty())throw error("RESOURCE_NOT_FOUND",HttpStatus.NOT_FOUND);
        var row=rows.getFirst();String state=(String)row.get("state");Instant expiry=(Instant)row.get("expires_at");
        if(!expiry.isAfter(clock.instant().plusSeconds(1)))throw error("UPLOAD_EXPIRED",HttpStatus.GONE);
        if(!Set.of("RESERVED","UPLOADING").contains(state))throw error("UPLOAD_STATE_CONFLICT",HttpStatus.CONFLICT);
        if(renew){
            var current=approval.approve(account,uuid((byte[])row.get("recording_id")),((Number)row.get("expected_size")).longValue(),(String)row.get("expected_sha256"));
            if(current.attempt()==null || !attempt.equals(current.attempt()))throw error("UPLOAD_STATE_CONFLICT",HttpStatus.CONFLICT);
        }
        // The first approval paid its issuance permit. Every later newly signed URL pays again.
        if(renew || !state.equals("RESERVED"))approval.issuePermit(account);
        var put=signer.sign(new StorageObjectKeys.Temporary(owner,uuid((byte[])row.get("recording_id")),attempt),expiry);
        if(!put.expiresAt().isAfter(clock.instant()) || put.expiresAt().isAfter(expiry)
            || put.expiresAt().isAfter(clock.instant().plusSeconds(600)))throw new IllegalStateException("Invalid signed URL lifetime");
        db.update("UPDATE recording_upload SET state='UPLOADING',updated_at=? WHERE user_id=? AND id=?",java.sql.Timestamp.from(clock.instant()),bytes(owner),bytes(attempt));
        return Map.of("attempt_id",attempt.toString(),"state","UPLOADING","put_url",put.url(),
            "expires_at",put.expiresAt().toString(),"attempt_expires_at",expiry.toString(),"headers",put.headers());
    }
    private static ApiException error(String code,HttpStatus status){return new ApiException(status,code,"업로드 시도 상태를 확인해 주세요.",false,Map.of());}
}
