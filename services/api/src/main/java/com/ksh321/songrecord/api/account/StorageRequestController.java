package com.ksh321.songrecord.api.account;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
import com.ksh321.songrecord.api.pagination.KeysetPages;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/storage/requests")
public final class StorageRequestController{
 private final StorageRequests requests;public StorageRequestController(StorageRequests requests){this.requests=requests;}
 @PostMapping(consumes=MediaType.APPLICATION_JSON_VALUE,produces=MediaType.APPLICATION_JSON_VALUE)
 public ResponseEntity<String> create(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestHeader(value="Idempotency-Key",required=false)String op,@RequestBody String body){var r=requests.create(auth,device,op,body);return ResponseEntity.status(r.status()).header("Cache-Control","no-store").contentType(MediaType.APPLICATION_JSON).body(r.body());}
 @GetMapping("/me") public ResponseEntity<KeysetPages.Page<Map<String,Object>>> list(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestParam MultiValueMap<String,String> params){return ResponseEntity.ok().header("Cache-Control","no-store").body(requests.list(auth,device,params));}
 @GetMapping("/{id}") public ResponseEntity<Map<String,Object>> get(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@PathVariable("id") String id){return ResponseEntity.ok().header("Cache-Control","no-store").body(requests.get(auth,device,id));}
}
