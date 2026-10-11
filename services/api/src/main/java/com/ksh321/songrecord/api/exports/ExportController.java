package com.ksh321.songrecord.api.exports;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.sync.SnapshotBuildStore;
import com.ksh321.songrecord.api.sync.SnapshotQueries;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import java.nio.ByteBuffer;
import org.springframework.http.*;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
import tools.jackson.databind.json.JsonMapper;

/** Export is a frozen metadata read, not a file lease or a sync acknowledgement. */
@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/exports")
public final class ExportController {
    private final AccountAccess access; private final IdempotentMutations receipts;
    private final SnapshotBuildStore builds; private final JobQueue jobs;
    private final SnapshotQueries queries; private final JdbcTemplate db;
    private final JsonMapper json=new JsonMapper();
    public ExportController(AccountAccess access,IdempotentMutations receipts,SnapshotBuildStore builds,
            JobQueue jobs,SnapshotQueries queries,JdbcTemplate db) {
        this.access=access;this.receipts=receipts;this.builds=builds;this.jobs=jobs;this.queries=queries;this.db=db;
    }
    @PostMapping(consumes="application/json",produces="application/json")
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String operation,@RequestBody String body) {
        var account=access.authenticate(auth,device);boolean include;
        try {var input=json.readTree(body);
            if(!input.isObject()||input.size()!=1||input.get("include_trash")==null||!input.get("include_trash").isBoolean())throw invalid();
            include=input.get("include_trash").asBoolean();
        } catch(ApiException e){throw e;}catch(RuntimeException e){throw invalid();}
        boolean includeTrash=include;
        var reply=receipts.execute(account,operation,"POST","/v1/exports",body,()->{
            var snapshot=builds.beginExportJoined(account,UUID.fromString(operation),includeTrash);
            var job=jobs.enqueue(account,JobQueue.Type.SNAPSHOT_BUILD,snapshot.id(),UUID.fromString(operation),"{}");
            return new IdempotentMutations.Reply(202,json.writeValueAsString(Map.of("export_id",snapshot.id().toString(),
                    "operation_id",job.toString(),"status","BUILDING","status_url","/v1/exports/"+snapshot.id()+"/manifest")));
        });
        return ResponseEntity.status(reply.status()).cacheControl(CacheControl.noStore()).contentType(MediaType.APPLICATION_JSON).body(reply.body());
    }
    @GetMapping(path="/{id}/manifest",produces="application/json")
    public ResponseEntity<Map<String,Object>> manifest(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,@PathVariable String id,
            @RequestParam MultiValueMap<String,String> params) {
        // The engine authenticates and fences ownership/TTL before any metadata is released.
        var account=access.authenticate(auth,device);
        UUID export;
        try {export=UUID.fromString(id);if(!export.toString().equals(id))throw invalid();}catch(IllegalArgumentException e){throw invalid();}
        var rows=db.queryForList("SELECT include_trash FROM export_session WHERE export_id=? AND user_id=?",bytes(export),bytes(access.revalidate(account).userId()));
        if(rows.isEmpty()){queries.getExport(auth,device,id,params);throw new ApiException(HttpStatus.NOT_FOUND,"EXPORT_NOT_FOUND","백업 기준을 다시 준비해 주세요.",false,Map.of());}
        var reply=queries.getExport(auth,device,id,params);
        var result=new LinkedHashMap<>(reply.body());result.put("export_id",id);
        Object choice=rows.getFirst().get("include_trash");
        result.put("source_user_id",access.revalidate(account).userId().toString());result.put("include_trash",choice instanceof Boolean b?b:((Number)choice).intValue()!=0);
        // Fence again after the ExportSession read; it cannot authorize an inactive account.
        access.revalidate(account);
        return ResponseEntity.status(reply.status()).cacheControl(CacheControl.noStore()).body(result);
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","include_trash를 확인해 주세요.",false,Map.of());}
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
