package com.ksh321.songrecord.api.recordings;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class TrashConfiguration {
    @Bean TrashRestoration trashRestoration(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,AccountChanges changes,RevisionChanges revisions,RecordingEditing editing){return new TrashRestoration(db,access,mutations,changes,revisions,editing,Clock.systemUTC());}
    @Bean TrashListing trashListing(JdbcTemplate db,AccountAccess access){return new TrashListing(db,access);}
    @Bean @Order(9) SecurityFilterChain trashSecurity(HttpSecurity http)throws Exception{
        http.securityMatcher("/v1/trash","/v1/trash/**").csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable()).authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/v1/trash").permitAll().requestMatchers(HttpMethod.POST,"/v1/trash/*/restore").permitAll().anyRequest().denyAll());return http.build();
    }
}
