package com.ksh321.songrecord.api.recordings;

import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/recordings")
public class RecordingController {
    private final RecordingDrafts drafts;
    private final RecordingSaving saving;
    private final RecordingListing listing;
    public RecordingController(RecordingDrafts drafts,RecordingSaving saving,RecordingListing listing){this.drafts=drafts;this.saving=saving;this.listing=listing;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<com.ksh321.songrecord.api.pagination.KeysetPages.Page<java.util.Map<String,Object>>> list(
            @RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestParam org.springframework.util.MultiValueMap<String,String> params){return ResponseEntity.ok().header("Cache-Control","no-store").body(listing.list(auth,device,params));}
    @PatchMapping(path="/{id}",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> save(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){
        var result=saving.save(auth,device,op,id,body);
        return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body){
        var result=drafts.create(auth,device,op,body);
        return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
}
