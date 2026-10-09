package com.ksh321.songrecord.api.retention;

import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController @Profile("!bootstrap") @RequestMapping("/v1/pins")
public final class PinController {
    private final PinSlots pins;
    public PinController(PinSlots pins){this.pins=pins;}
    @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> reserve(@RequestHeader(value="Authorization",required=false) String auth,
        @RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@RequestBody String body){
        var result=pins.reserve(auth,device,op,body);return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
    @PostMapping(path="/{slotNo}/replacement",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> replace(@RequestHeader(value="Authorization",required=false) String auth,
        @RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("slotNo") String slot,@RequestBody String body){
        var result=pins.replace(auth,device,op,slot,body);return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }
    @DeleteMapping(path="/{slotNo}",consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> release(@RequestHeader(value="Authorization",required=false) String auth,
        @RequestHeader(value="X-Device-Id",required=false) String device,@RequestHeader(value="Idempotency-Key",required=false) String op,@PathVariable("slotNo") String slot,@RequestBody String body){
        var result=pins.release(auth,device,op,slot,body);return ResponseEntity.status(result.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(result.body());
    }

}
