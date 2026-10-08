package com.ksh321.songrecord.api.uploads;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Receipt, upload transition and durable submission share one transaction. No object I/O here. */
public final class UploadCompletion {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate db; private final AccountAccess access; private final IdempotentMutations mutations;
    private final UploadReservations reservations; private final JobQueue jobs; private final Clock clock;
    public UploadCompletion(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,
            IdempotentMutations mutations,JobQueue jobs,Clock clock){
        this.db=db;this.access=access;this.mutations=mutations;this.jobs=jobs;this.clock=clock;
        reservations=new UploadReservations(db,access,manager,clock);
    }
    public IdempotentMutations.Reply complete(String auth,String device,String operation,UUID attempt){
        var account=access.authenticate(auth,device);
        return mutations.execute(account,operation,"POST","/v1/uploads/"+attempt+"/complete","{}",()->
            reservations.locked(account,()->accept(account,attempt)));
    }
    private IdempotentMutations.Reply accept(AccountAccess.Account account,UUID attempt){
        UUID owner=access.revalidate(account).userId();
        var rows=db.query("SELECT state,expires_at FROM recording_upload WHERE user_id=? AND id=? FOR UPDATE",(rs,n)->Map.entry(rs.getString("state"),rs.getTimestamp("expires_at").toInstant()),bytes(owner),bytes(attempt));
        if(rows.isEmpty())throw error("RESOURCE_NOT_FOUND",HttpStatus.NOT_FOUND);
        var row=rows.getFirst();String state=row.getKey();
        if(state.equals("COMMITTED"))return reply(200,Map.of("attempt_id",attempt.toString(),"state","COMMITTED"));
        if(!Set.of("UPLOADING","VERIFYING").contains(state))throw error("UPLOAD_STATE_CONFLICT",HttpStatus.CONFLICT);
        if(!row.getValue().isAfter(clock.instant()))throw error("UPLOAD_EXPIRED",HttpStatus.GONE);
        // Attempt identity, not the HTTP operation, deduplicates separate completion requests too.
        UUID job=jobs.enqueue(account,JobQueue.Type.UPLOAD_VERIFY,attempt,attempt,"{}");
        db.update("UPDATE recording_upload SET state='VERIFYING',updated_at=? WHERE user_id=? AND id=?",java.sql.Timestamp.from(clock.instant()),bytes(owner),bytes(attempt));
        return reply(202,Map.of("attempt_id",attempt.toString(),"state","VERIFYING","job_id",job.toString()));
    }
    private static IdempotentMutations.Reply reply(int status,Map<String,String> body){return new IdempotentMutations.Reply(status,JSON.writeValueAsString(body));}
    private static ApiException error(String code,HttpStatus status){return new ApiException(status,code,"업로드 시도 상태를 확인해 주세요.",false,Map.of());}
}
