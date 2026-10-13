package com.ksh321.songrecord.api.account;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.*;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/account")
public class DeletionDeviceController {
 private final DeletionDeviceProofs proofs;
 public DeletionDeviceController(DeletionDeviceProofs proofs){this.proofs=proofs;}
 @PostMapping("/deletion-device-confirmations")
 public ResponseEntity<?> confirm(@RequestBody Owner body,@RequestHeader(value="X-Deletion-Device-Proof",required=false)String proof){return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(proofs.confirm(body.user_id(),body.device_id(),proof));}
 public record Owner(String user_id,String device_id){}
}
