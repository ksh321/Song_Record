package com.ksh321.songrecord.api.account;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController @Profile("!bootstrap")
public class DeletionWebPageController {
 @GetMapping({"/account-deletion","/account-deletion/index.html"}) public ResponseEntity<?> index(){return asset("index.html",MediaType.TEXT_HTML);}
 @GetMapping("/account-deletion/main.js")public ResponseEntity<?> javascript(){return asset("main.js",MediaType.parseMediaType("text/javascript"));}
 @GetMapping("/account-deletion/style.css")public ResponseEntity<?> stylesheet(){return asset("style.css",MediaType.parseMediaType("text/css"));}
 private ResponseEntity<?> asset(String name,MediaType type){return ResponseEntity.ok().cacheControl(CacheControl.noStore()).contentType(type)
  .header("Content-Security-Policy","default-src 'none'; script-src 'self' https://accounts.google.com/gsi/client; style-src 'self' https://accounts.google.com/gsi/style; connect-src 'self' https://accounts.google.com/gsi/; frame-src https://accounts.google.com/gsi/; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
  .header("Cross-Origin-Opener-Policy","same-origin-allow-popups").header("Referrer-Policy","strict-origin-when-cross-origin").header("X-Content-Type-Options","nosniff").body(new ClassPathResource("deletion-web/"+name));}
}
