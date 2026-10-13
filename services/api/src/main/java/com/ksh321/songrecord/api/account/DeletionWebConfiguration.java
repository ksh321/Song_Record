package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import java.net.URI;
import java.time.Clock;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.scheduling.annotation.Scheduled;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class DeletionWebConfiguration {
 @Bean(destroyMethod="close") DeletionWebProofs deletionWebProofs(@Value("${account.deletion.web.enabled:false}")boolean enabled,@Value("${account.deletion.web.origin:}")String origin,@Value("${account.deletion.web.google-client-id:}")String google,@Value("${account.deletion.web.kakao-rest-key:}")String kakao,@Value("${account.deletion.web.kakao-client-secret:}")String secret)throws Exception{
  if(enabled){var u=URI.create(origin);if(!"https".equals(u.getScheme())||u.getHost()==null||u.getUserInfo()!=null||u.getQuery()!=null||u.getFragment()!=null||!u.getPath().isEmpty())throw new IllegalArgumentException("Deletion web requires a fixed HTTPS origin without path");}
  return new DeletionWebProofs(enabled?google:"",enabled?kakao:"",enabled?secret:"",enabled?origin:"",Clock.systemUTC());
 }
 @Bean DeletionWebOwnership deletionWebOwnership(JdbcTemplate db,AccountRegistrationService registrations,SessionService sessions,AccountDeletion deletion,DeletionWebProofs proofs,PlatformTransactionManager tx,@Value("${account.deletion.web.enabled:false}")boolean enabled,@Value("${account.deletion.web.rate-secret:}")String pepper,@Value("${account.deletion.web.google-client-id:}")String google,@Value("${account.deletion.web.kakao-rest-key:}")String kakao){
  if(enabled&&pepper.length()<32)throw new IllegalArgumentException("Deletion web rate secret required");
  Map<String,String> clients=new LinkedHashMap<>();if(enabled&&!google.isBlank())clients.put("GOOGLE",google);if(enabled&&!kakao.isBlank())clients.put("KAKAO",kakao);
  return new DeletionWebOwnership(db,registrations,sessions,deletion,proofs::verify,Clock.systemUTC(),enabled?pepper:"",clients,tx);
 }
 @Bean @Order(2) SecurityFilterChain deletionWebSecurity(HttpSecurity http)throws Exception{
  return http.securityMatcher("/account-deletion","/account-deletion/**","/v1/account/web/**").csrf(c->c.disable()).requestCache(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
   .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/account-deletion","/account-deletion/index.html","/account-deletion/main.js","/account-deletion/style.css","/v1/account/web/configuration","/v1/account/web/kakao-callback").permitAll().requestMatchers(HttpMethod.POST,"/v1/account/web/challenges","/v1/account/web/preparations").permitAll().anyRequest().denyAll()).build();
 }
 @Bean WebChallengeMaintenance webChallengeMaintenance(DeletionWebOwnership service){return new WebChallengeMaintenance(service);}
 static final class WebChallengeMaintenance {
  private final DeletionWebOwnership service;WebChallengeMaintenance(DeletionWebOwnership service){this.service=service;}
  @Scheduled(initialDelay=60000,fixedDelay=60000,scheduler="storageRequestScheduler") public void prune(){try{service.prune();}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(WebChallengeMaintenance.class).warn("Deletion web challenge maintenance deferred");}}
 }
}
