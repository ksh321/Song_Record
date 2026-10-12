package com.ksh321.songrecord.api.account;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/account")
public class AccountDeletionController {
 private final AccountDeletion service;
 public AccountDeletionController(AccountDeletion service){this.service=service;}
 @PostMapping("/deletion-reauth-challenges") public ResponseEntity<?> challenge(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestBody Challenge input){return ok(service.challenge(auth,device,input.provider()));}
 @PostMapping("/deletion-status-preparations") public ResponseEntity<?> prepare(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestBody Preparation input){return ok(service.prepare(auth,device,input.challenge_id(),input.proof()));}
 @PostMapping("/deletion-requests") public ResponseEntity<?> accept(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String operation,@RequestHeader(value="X-Deletion-Status-Token",required=false)String token,@RequestBody String body){var reply=service.accept(auth,device,operation,token,body);return ResponseEntity.status(reply.status()).cacheControl(CacheControl.noStore()).contentType(MediaType.APPLICATION_JSON).body(reply.body());}
 @GetMapping("/deletion-status/{id}") public ResponseEntity<?> status(@PathVariable("id")String id,@RequestHeader(value="X-Deletion-Status-Token",required=false)String token){return ok(service.status(id,token));}
 private ResponseEntity<?> ok(Object body){return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);}
 public record Challenge(String provider){}
 public record Preparation(String challenge_id,String proof){@Override public String toString(){return "Preparation[REDACTED]";}}
}
