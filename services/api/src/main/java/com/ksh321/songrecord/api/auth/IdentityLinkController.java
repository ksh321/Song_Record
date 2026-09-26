package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/auth/identities")
public class IdentityLinkController {
    private final IdentityLinkService links;
    public IdentityLinkController(IdentityLinkService links){this.links=links;}
    @GetMapping public ResponseEntity<?> list(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device){return ok(Map.of("identities",links.identities(token(auth),id(device))));}
    @PostMapping("/reauth-challenges") public ResponseEntity<?> begin(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,@RequestBody Begin request){
        return ok(links.begin(token(auth),id(device),request.provider(),request.targetProvider()));
    }
    @PostMapping("/link-challenges") public ResponseEntity<?> reauth(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,@RequestBody Proof request){
        return ok(links.reauthenticate(token(auth),id(device),id(request.challengeId()),request.proof()));
    }
    @PostMapping("/link") public ResponseEntity<?> link(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,@RequestBody Proof request){
        links.link(token(auth),id(device),id(request.challengeId()),request.proof());return ok(Map.of("linked",true));
    }
    private static String token(String value){if(value==null || !value.startsWith("Bearer "))throw invalid();return value.substring(7);}
    private static UUID id(String value){try{var id=UUID.fromString(value);if(!id.toString().equals(value))throw invalid();return id;}catch(IllegalArgumentException|NullPointerException e){throw invalid();}}
    private static com.ksh321.songrecord.api.web.ApiException invalid(){return new com.ksh321.songrecord.api.web.ApiException(org.springframework.http.HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","다시 로그인해 주세요.",false,Map.of());}
    private static ResponseEntity<?> ok(Object body){return ResponseEntity.ok().header("Cache-Control","no-store").header("Pragma","no-cache").body(body);}
    public record Begin(String provider,String targetProvider) {}
    public record Proof(String challengeId,String proof){@Override public String toString(){return "Proof[REDACTED]";}}
}
