package com.ksh321.songrecord.api.songs;

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
public class SongConfiguration {
    @Bean SongRepresentative songRepresentative(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes){return new SongRepresentative(jdbc,access,mutations,revisions,changes);}
    @Bean SongEditing songEditing(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes){return new SongEditing(jdbc,access,mutations,revisions,changes);}
    @Bean SongListing songListing(AccountAccess access,com.ksh321.songrecord.api.pagination.KeysetPages pages){return new SongListing(access,pages);}
    @Bean SongCreation songCreation(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,AccountChanges changes,TjCandidates candidates,com.ksh321.songrecord.api.revision.RevisionChanges revisions){return new SongCreation(jdbc,access,mutations,guard,changes,candidates,Clock.systemUTC(),revisions);}
    @Bean @Order(2) SecurityFilterChain songSecurity(HttpSecurity http) throws Exception {
        http.securityMatcher("/v1/songs","/v1/songs/**").csrf(c->c.disable())
            .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable())
            // Controller always authenticates bearer + device through AccountAccess before parsing input.
            .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.POST,"/v1/songs").permitAll().requestMatchers(HttpMethod.GET,"/v1/songs").permitAll().requestMatchers(HttpMethod.PATCH,"/v1/songs/*").permitAll().requestMatchers(HttpMethod.PUT,"/v1/songs/*/representative").permitAll().anyRequest().denyAll());
        return http.build();
    }
}
