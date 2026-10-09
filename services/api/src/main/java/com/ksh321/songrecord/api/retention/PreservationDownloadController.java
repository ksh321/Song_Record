package com.ksh321.songrecord.api.retention;
import java.util.*;import org.springframework.context.annotation.Profile;import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;import org.springframework.http.ResponseEntity;import org.springframework.web.bind.annotation.*;
@RestController @Profile("!bootstrap") @ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
@RequestMapping("/v1")
public final class PreservationDownloadController {
 private final PreservationDownloads downloads;public PreservationDownloadController(PreservationDownloads downloads){this.downloads=downloads;}
 @GetMapping("/recordings/{id}/preservation-url") public ResponseEntity<Map<String,Object>> ticket(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@PathVariable("id")UUID id){return ResponseEntity.ok().header("Cache-Control","no-store").body(downloads.ticket(auth,device,id));}
}
