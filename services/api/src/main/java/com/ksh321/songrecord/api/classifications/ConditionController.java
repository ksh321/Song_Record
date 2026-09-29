package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

@RestController @Profile("!bootstrap") @RequestMapping("/v1/conditions")
public class ConditionController {
    private final ConditionService conditions;
    public ConditionController(ConditionService conditions){this.conditions=conditions;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ConditionService.Catalog> list(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestParam MultiValueMap<String,String> params,jakarta.servlet.http.HttpServletRequest request){var catalog=conditions.list(auth,device,params);return ResponseEntity.ok().header("Cache-Control","no-store").body("HEAD".equals(request.getMethod())?null:catalog);}
    @PostMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody(required=false) String body){return reply(conditions.create(auth,device,op,body));}
    @PatchMapping(path="/{id}",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> rename(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody(required=false) String body){return reply(conditions.rename(auth,device,op,id,body));}
    @PostMapping(path="/{id}/archive",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> archive(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody(required=false) String body){return reply(conditions.archive(auth,device,op,id,body));}
    private static ResponseEntity<String> reply(IdempotentMutations.Reply reply){return ResponseEntity.status(reply.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(reply.body());}
}
