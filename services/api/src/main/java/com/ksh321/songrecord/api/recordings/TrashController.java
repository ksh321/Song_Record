package com.ksh321.songrecord.api.recordings;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/trash")
public class TrashController {
    private final TrashRestoration restoration;private final TrashListing listing;private final TrashPurge purge;
    public TrashController(TrashRestoration restoration,TrashListing listing,TrashPurge purge){this.restoration=restoration;this.listing=listing;this.purge=purge;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<java.util.Map<String,Object>> list(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit){return ResponseEntity.ok().header("Cache-Control","no-store").body(listing.list(auth,device,cursor,limit));}
    @PostMapping(path="/{batchId}/restore",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> restore(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,@PathVariable("batchId")String id,@RequestBody String body){var reply=restoration.restore(auth,device,op,id,body);return ResponseEntity.status(reply.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(reply.body());}
    @PostMapping(path="/{batchId}/purge",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> purge(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,@PathVariable("batchId")String id,@RequestBody String body){var reply=purge.purge(auth,device,op,id,body);return ResponseEntity.status(reply.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(reply.body());}
}
