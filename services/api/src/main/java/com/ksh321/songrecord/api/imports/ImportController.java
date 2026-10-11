package com.ksh321.songrecord.api.imports;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.sync.SnapshotBuildStore;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import tools.jackson.databind.json.JsonMapper;

/** ZIP ownership is a comparison only. Authority always comes from the live session. */
@RestController @Profile("!bootstrap") @RequestMapping("/v1/imports")
public final class ImportController {
    private final AccountAccess access; private final IdempotentMutations receipts;
    private final SnapshotBuildStore builds; private final JobQueue jobs;
    private final JsonMapper json=new JsonMapper();
    public ImportController(AccountAccess access,IdempotentMutations receipts,SnapshotBuildStore builds,JobQueue jobs) {
        this.access=access;this.receipts=receipts;this.builds=builds;this.jobs=jobs;
    }
    @PostMapping(path="/preflight",consumes="application/json",produces="application/json")
    public ResponseEntity<String> preflight(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String operation,@RequestBody String body) {
        var account=access.authenticate(auth,device);
        UUID source;
        try {
            var input=json.readTree(body);
            if(!input.isObject()||input.size()!=2||input.get("schema_version")==null
                ||!input.get("schema_version").isIntegralNumber()||!input.get("schema_version").toString().equals("1")
                ||input.get("source_user_id")==null||!input.get("source_user_id").isString())throw invalid();
            String value=input.get("source_user_id").asString();source=UUID.fromString(value);
            if(!source.toString().equals(value))throw invalid();
        }catch(ApiException e){throw e;}catch(RuntimeException e){throw invalid();}
        if(!access.revalidate(account).userId().equals(source))
            throw new ApiException(HttpStatus.FORBIDDEN,"IMPORT_ACCOUNT_MISMATCH","동일 계정의 백업만 가져올 수 있습니다.",false,Map.of());
        var reply=receipts.execute(account,operation,"POST","/v1/imports/preflight",body,()->{
            var snapshot=builds.beginJoined(account,UUID.fromString(operation),1);
            var job=jobs.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,snapshot.id(),UUID.fromString(operation),"{}");
            return new IdempotentMutations.Reply(202,json.writeValueAsString(Map.of(
                "operation_id",job.toString(),"snapshot_token",snapshot.id().toString(),
                "status","BUILDING","status_url","/v1/sync/snapshots/"+snapshot.id())));
        });
        access.revalidate(account);
        return ResponseEntity.status(reply.status()).cacheControl(CacheControl.noStore()).contentType(MediaType.APPLICATION_JSON).body(reply.body());
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","백업 형식 버전과 계정을 확인해 주세요.",false,Map.of());}
}
