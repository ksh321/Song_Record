package com.ksh321.songrecord.api.songs;

import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/songs")
public class SongController {
    private final SongCreation creation;
    private final SongListing listing;
    private final SongEditing editing;
    private final SongRepresentative representative;
    public SongController(SongCreation creation,SongListing listing,SongEditing editing,SongRepresentative representative){this.creation=creation;this.listing=listing;this.editing=editing;this.representative=representative;}
    @PutMapping(path="/{id}/representative",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> representative(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){
        var result=representative.put(auth,device,op,id,body);
        return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
    @PatchMapping(path="/{id}",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> patch(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("id") String id,@RequestBody String body){
        var result=editing.patch(auth,device,op,id,body);
        return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<com.ksh321.songrecord.api.pagination.KeysetPages.Page<java.util.Map<String,Object>>> list(
            @RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestParam org.springframework.util.MultiValueMap<String,String> params){
        return ResponseEntity.ok().header("Cache-Control","no-store").body(listing.list(auth,device,params));
    }
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body){
        var result=creation.create(auth,device,op,body);
        return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
}
