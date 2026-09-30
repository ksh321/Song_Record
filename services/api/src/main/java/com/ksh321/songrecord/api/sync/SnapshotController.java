package com.ksh321.songrecord.api.sync;

import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/sync/snapshots")
public class SnapshotController {
    private final SnapshotRequests requests;
    private final SnapshotQueries queries;
    public SnapshotController(SnapshotRequests requests,SnapshotQueries queries){this.requests=requests;this.queries=queries;}
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body) {
        var result=requests.create(auth,device,op,body);
        return ResponseEntity.status(result.status()).cacheControl(CacheControl.noStore()).contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
    @GetMapping(path="/{token}",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String,Object>> get(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,@PathVariable("token") String token,
            @RequestParam MultiValueMap<String,String> params) {
        var result=queries.get(auth,device,token,params);
        return ResponseEntity.status(result.status()).cacheControl(CacheControl.noStore()).body(result.body());
    }
}
