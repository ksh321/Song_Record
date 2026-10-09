package com.ksh321.songrecord.api.uploads;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
@RestController @Profile("!bootstrap") @ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
@RequestMapping("/v1")
public final class UploadController {
    private final UploadUrls urls; private final UploadCompletion completion;
    public UploadController(UploadUrls urls,UploadCompletion completion){this.urls=urls;this.completion=completion;}
    @PostMapping(path="/recordings/{id}/uploads",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> authorize(@RequestHeader(value="Authorization",required=false)String auth,
        @RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,
        @PathVariable("id")UUID id,@RequestBody String body){return response(urls.authorize(auth,device,op,id,body));}
    @PostMapping(path="/uploads/{id}/renew-url",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> renew(@RequestHeader(value="Authorization",required=false)String auth,
        @RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,
        @PathVariable("id")UUID id){return response(urls.renew(auth,device,op,id));}
    @PostMapping(path="/uploads/{id}/complete",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> complete(@RequestHeader(value="Authorization",required=false)String auth,
        @RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,
        @PathVariable("id")UUID id){return response(completion.complete(auth,device,op,id));}
    @PostMapping(path="/uploads/{id}/cancel",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> cancel(@RequestHeader(value="Authorization",required=false)String auth,
        @RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,
        @PathVariable("id")UUID id){return response(completion.cancel(auth,device,op,id));}
    private static ResponseEntity<String> response(IdempotentMutations.Reply r){return ResponseEntity.status(r.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(r.body());}
}
