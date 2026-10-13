package com.ksh321.songrecord.api.account;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.time.*;
import java.util.*;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/account/web")
public class DeletionWebController {
 private final DeletionWebOwnership service;private final DeletionWebProofs proofs;
 public DeletionWebController(DeletionWebOwnership service,DeletionWebProofs proofs){this.service=service;this.proofs=proofs;}
 @GetMapping("/configuration")public ResponseEntity<?> configuration(HttpServletRequest request){requireSecure(request);return ok(service.configuration());}
 @PostMapping("/challenges")public ResponseEntity<?> challenge(@RequestBody Challenge body,HttpServletRequest request){requireSecure(request);return ok(service.challenge(body.provider(),request.getRemoteAddr()));}
 @PostMapping("/preparations")public ResponseEntity<?> prepare(@RequestBody Preparation body,HttpServletRequest request){requireSecure(request);return ok(service.prepare(body.challenge_id(),body.proof()));}
 @GetMapping("/kakao-callback")public ResponseEntity<String> callback(@RequestParam(value="state",required=false)String state,@RequestParam(value="code",required=false)String code,HttpServletRequest request){
  requireSecure(request);
  var row=service.kakaoState(state);var token=proofs.kakaoCode(code);
  var at=row.get("created_at") instanceof java.sql.Timestamp t?t.toLocalDateTime():(LocalDateTime)row.get("created_at");
  proofs.verify("KAKAO",token,(byte[])row.get("nonce_hash"),at.toInstant(ZoneOffset.UTC));
  var id=com.ksh321.songrecord.api.songs.SongQueryKeys.uuid((byte[])row.get("id")).toString();
  var json=new tools.jackson.databind.json.JsonMapper();String message=json.writeValueAsString(Map.of("type","song-record-deletion-proof","challenge_id",id,"state",state,"proof",token));
  String nonce=UUID.randomUUID().toString();String target=json.writeValueAsString(proofs.origin());
  String html="<!doctype html><html lang=\"ko\"><meta charset=\"utf-8\"><title>소유 확인</title><p>소유 확인 결과를 원래 창으로 전달합니다. 전달되지 않으면 원래 창에서 다시 진행해 주세요.</p><script nonce=\""+nonce+"\">if(window.opener){window.opener.postMessage("+message+","+target+");window.close();}</script></html>";
  return ResponseEntity.ok().cacheControl(CacheControl.noStore()).header("Content-Security-Policy","default-src 'none'; script-src 'nonce-"+nonce+"'; frame-ancestors 'none'; base-uri 'none'").header("Referrer-Policy","no-referrer").contentType(MediaType.TEXT_HTML).body(html);
 }
 private ResponseEntity<?> ok(Object body){return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);}
 private void requireSecure(HttpServletRequest request){if(Boolean.TRUE.equals(service.configuration().get("enabled"))&&!request.isSecure())throw new com.ksh321.songrecord.api.web.ApiException(HttpStatus.FORBIDDEN,"DELETION_WEB_HTTPS_REQUIRED","보안 연결에서 계정 소유 확인을 진행해 주세요.",false,Map.of());}
 public record Challenge(String provider){}
 public record Preparation(String challenge_id,String proof){@Override public String toString(){return "Preparation[REDACTED]";}}
}
