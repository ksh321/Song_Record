package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class AccountDeletionConfiguration {
 @Bean AccountDeletion accountDeletion(JdbcTemplate db,AccountAccess access,LinkProofVerifier proofs,IdempotentMutations mutations,PlatformTransactionManager tx){return new AccountDeletion(db,access,proofs,mutations,tx,Clock.systemUTC());}
 @Bean DeletionDeviceProofs deletionDeviceProofs(JdbcTemplate db){return new DeletionDeviceProofs(db,Clock.systemUTC());}
 @Bean @Order(3) SecurityFilterChain accountDeletionSecurity(HttpSecurity http)throws Exception{
  return http.securityMatcher("/v1/account/**").csrf(c->c.disable()).requestCache(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
   .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.POST,"/v1/account/deletion-reauth-challenges","/v1/account/deletion-status-preparations","/v1/account/deletion-requests","/v1/account/deletion-device-confirmations").permitAll().requestMatchers(HttpMethod.GET,"/v1/account/deletion-status/*").permitAll().anyRequest().denyAll()).build();
 }
}
