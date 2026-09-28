package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

@RestController @Profile("!bootstrap") @RequestMapping("/v1/tags")
public class TagController {
    private final TagService tags;
    public TagController(TagService tags){this.tags=tags;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<KeysetPages.Page<Map<String,Object>>> list(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestParam MultiValueMap<String,String> params){return ResponseEntity.ok().header("Cache-Control","no-store").body(tags.list(auth,device,params));}
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body){return reply(tags.create(auth,device,op,body));}
    @PatchMapping(path="/{id}",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> rename(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){return reply(tags.rename(auth,device,op,id,body));}
    @PostMapping(path="/{id}/archive",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> archive(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){return reply(tags.archive(auth,device,op,id,body));}
    private static ResponseEntity<String> reply(IdempotentMutations.Reply reply){return ResponseEntity.status(reply.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(reply.body());}
}
