package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.revision.CreationGuard;
import com.ksh321.songrecord.api.sync.AccountChanges;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class RecordingConfiguration {
    @Bean RecordingSaving recordingSaving(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes,RecordingDrafts drafts){return new RecordingSaving(jdbc,access,mutations,revisions,changes,drafts);}
    @Bean RecordingDrafts recordingDrafts(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,AccountChanges changes){return new RecordingDrafts(jdbc,access,mutations,guard,changes,Clock.systemUTC());}
    @Bean @Order(3) SecurityFilterChain recordingSecurity(HttpSecurity http)throws Exception{
        http.securityMatcher("/v1/recordings","/v1/recordings/**").csrf(c->c.disable())
            .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable())
            .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.POST,"/v1/recordings").permitAll().requestMatchers(HttpMethod.PATCH,"/v1/recordings/*").permitAll().anyRequest().denyAll());
        return http.build();
    }
}
