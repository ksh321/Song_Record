package com.ksh321.songrecord.api.retention;

import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController @Profile("!bootstrap") @RequestMapping("/v1")
public final class RetentionController {
    private final RetentionQueries query;
    public RetentionController(RetentionQueries query){this.query=query;}
    @GetMapping("/recordings/{id}/retention")
    public ResponseEntity<Map<String,Object>> retention(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@PathVariable("id")String id){return ResponseEntity.ok().header("Cache-Control","no-store").body(query.retention(auth,device,id));}
    @GetMapping("/storage")
    public ResponseEntity<Map<String,Object>> storage(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device){return ResponseEntity.ok().header("Cache-Control","no-store").body(query.storage(auth,device));}
}
