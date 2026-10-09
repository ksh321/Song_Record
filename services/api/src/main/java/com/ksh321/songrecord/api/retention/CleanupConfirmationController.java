package com.ksh321.songrecord.api.retention;
import org.springframework.context.annotation.Profile;import org.springframework.http.*;import org.springframework.web.bind.annotation.*;import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/storage")
public final class CleanupConfirmationController {
 private final CleanupConfirmations service;public CleanupConfirmationController(CleanupConfirmations service){this.service=service;}
 @PostMapping(path="/cleanup-previews",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
 public ResponseEntity<String> preview(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,@RequestBody String body){return reply(service.preview(auth,device,op,body));}
 @PostMapping(path="/cleanup-confirmations",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
 public ResponseEntity<String> confirm(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,@RequestBody String body){return reply(service.confirm(auth,device,op,body));}
 private static ResponseEntity<String> reply(IdempotentMutations.Reply r){return ResponseEntity.status(r.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(r.body());}
}
