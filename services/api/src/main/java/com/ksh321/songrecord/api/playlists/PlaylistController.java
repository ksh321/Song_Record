package com.ksh321.songrecord.api.playlists;

import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

@RestController @Profile("!bootstrap") @RequestMapping("/v1/playlists")
public class PlaylistController {
    private final PlaylistService playlists;
    public PlaylistController(PlaylistService playlists){this.playlists=playlists;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<KeysetPages.Page<Map<String,Object>>> list(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestParam MultiValueMap<String,String> params){return ResponseEntity.ok().header("Cache-Control","no-store").body(playlists.list(auth,device,params));}
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body){return reply(playlists.create(auth,device,op,body));}
    @PatchMapping(path="/{id}",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> rename(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){return reply(playlists.rename(auth,device,op,id,body));}
    @DeleteMapping(path="/{id}",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> delete(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){return reply(playlists.delete(auth,device,op,id,body));}
    private static ResponseEntity<String> reply(IdempotentMutations.Reply reply){return ResponseEntity.status(reply.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(reply.body());}
    @GetMapping(path="/{id}/items",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String,Object>> items(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@PathVariable("id") String id){return ResponseEntity.ok().header("Cache-Control","no-store").body(playlists.items(auth,device,id));}
    @PostMapping(path="/{id}/items",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> add(@RequestHeader(value="Authorization",required=false) String auth,@RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){return reply(playlists.addItem(auth,device,op,id,body));}
}
