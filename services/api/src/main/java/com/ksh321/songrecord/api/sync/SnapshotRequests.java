package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.json.JsonMapper;

/** Durable submission only. No external work or source extraction inside the request transaction. */
public final class SnapshotRequests {
    private final AccountAccess access;
    private final IdempotentMutations receipts;
    private final SnapshotBuildStore builds;
    private final JobQueue jobs;
    private final JsonMapper json=new JsonMapper();
    public SnapshotRequests(AccountAccess access,IdempotentMutations receipts,SnapshotBuildStore builds,JobQueue jobs) {
        this.access=access;this.receipts=receipts;this.builds=builds;this.jobs=jobs;
    }
    public IdempotentMutations.Reply create(String authorization,String device,String operation,String body) {
        var account=access.authenticate(authorization,device);
        try {
            var input=json.readTree(body);
            if(!input.isObject()||input.size()!=1||input.get("schema_version")==null
                    ||!input.get("schema_version").isIntegralNumber()||!input.get("schema_version").toString().equals("1"))
                throw invalid();
        }catch(ApiException e){throw e;}catch(RuntimeException e){throw invalid();}
        return receipts.execute(account,operation,"POST","/v1/sync/snapshots",body,()->{
            // The receipt boundary validates the canonical UUID before this callback.
            var attempt=builds.beginJoined(account,UUID.fromString(operation),1);
            UUID job=jobs.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,attempt.id(),UUID.fromString(operation),"{}");
            return new IdempotentMutations.Reply(202,json.writeValueAsString(Map.of(
                    "operation_id",job.toString(),"snapshot_token",attempt.id().toString(),
                    "status","BUILDING","status_url","/v1/sync/snapshots/"+attempt.id())));
        });
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","schema_version=1로 요청해 주세요.",false,Map.of());}
}
