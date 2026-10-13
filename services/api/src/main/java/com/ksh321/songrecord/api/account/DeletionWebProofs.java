package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.nimbusds.jose.jwk.source.*;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jose.util.DefaultResourceRetriever;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;

/** Dedicated web audiences; native app keys are never treated as a web OAuth client. */
public final class DeletionWebProofs implements AutoCloseable {
 private final Map<String,LinkOidcVerifier> verifiers=new HashMap<>();private final List<JWKSource<SecurityContext>> sources=new ArrayList<>();
 private final String kakao,secret,origin;private final Clock clock;
 private final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).followRedirects(HttpClient.Redirect.NEVER).build();
 public DeletionWebProofs(String google,String kakao,String secret,String origin,Clock clock)throws Exception{
  this.kakao=kakao;this.secret=secret;this.origin=origin;this.clock=clock;
  if(!google.isBlank())add("GOOGLE",google,Set.of("https://accounts.google.com","accounts.google.com"),"https://www.googleapis.com/oauth2/v3/certs");
  if(!kakao.isBlank())add("KAKAO",kakao,Set.of("https://kauth.kakao.com"),"https://kauth.kakao.com/.well-known/jwks.json");
 }
 private void add(String provider,String audience,Set<String> issuers,String url)throws Exception{
  var keys=JWKSourceBuilder.<SecurityContext>create(URI.create(url).toURL(),new DefaultResourceRetriever(2000,3000,65536)).cache(300000,5000).refreshAheadCache(false).retrying(false).build();sources.add(keys);
  verifiers.put(provider,new LinkOidcVerifier(provider,audience,issuers,keys,clock));
 }
 public VerifiedProviderIdentity verify(String provider,String proof,byte[] nonce,Instant at){var v=verifiers.get(provider);if(v==null)throw DeletionWebOwnership.unavailable();return v.verify(proof,nonce,at);}
 public String kakaoCode(String code){
  if(kakao.isBlank()||origin.isBlank()||code==null||code.isBlank()||code.length()>2048)throw DeletionWebOwnership.unavailable();
  var fields=new LinkedHashMap<String,String>();fields.put("grant_type","authorization_code");fields.put("client_id",kakao);fields.put("redirect_uri",origin+"/v1/account/web/kakao-callback");fields.put("code",code);if(!secret.isBlank())fields.put("client_secret",secret);
  var body=String.join("&",fields.entrySet().stream().map(e->encode(e.getKey())+"="+encode(e.getValue())).toList());
  try{
   var request=HttpRequest.newBuilder(URI.create("https://kauth.kakao.com/oauth/token")).timeout(Duration.ofSeconds(10)).header("Content-Type","application/x-www-form-urlencoded").POST(HttpRequest.BodyPublishers.ofString(body)).build();
   var response=http.send(request,HttpResponse.BodyHandlers.ofInputStream());try(var input=response.body()){
    byte[] bytes=input.readNBytes(65537);if(response.statusCode()!=200||bytes.length>65536)throw DeletionWebOwnership.unavailable();
    var json=new tools.jackson.databind.json.JsonMapper().readTree(bytes);String token=json.path("id_token").asText();if(!token.matches("[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+")||token.length()>16384)throw DeletionWebOwnership.unavailable();return token;
   }
  }catch(InterruptedException e){Thread.currentThread().interrupt();throw DeletionWebOwnership.unavailable();}catch(java.io.IOException|RuntimeException e){throw DeletionWebOwnership.unavailable();}
 }
 public String origin(){return origin;}
 private static String encode(String s){return URLEncoder.encode(s,StandardCharsets.UTF_8);}
 public void close()throws Exception{http.close();for(var key:sources)if(key instanceof AutoCloseable c)c.close();}
}
