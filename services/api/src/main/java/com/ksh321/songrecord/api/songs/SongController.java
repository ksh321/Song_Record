package com.ksh321.songrecord.api.songs;

import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/songs")
public class SongController {
    private final SongCreation creation;
    public SongController(SongCreation creation){this.creation=creation;}
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,
            @RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body){
        var result=creation.create(auth,device,op,body);
        return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
}
