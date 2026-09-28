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
    @Bean RecordingLinking recordingLinking(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes,RecordingEditing editing,com.ksh321.songrecord.api.jobs.JobQueue jobs){return new RecordingLinking(jdbc,access,mutations,revisions,changes,editing,jobs);}
    @Bean RecordingRating recordingRating(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes,RecordingEditing editing,com.ksh321.songrecord.api.jobs.JobQueue jobs){return new RecordingRating(jdbc,access,mutations,revisions,changes,editing,jobs);}
    @Bean RecordingEditing recordingEditing(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes,RecordingDrafts drafts,RecordingSaving saving,com.ksh321.songrecord.api.jobs.JobQueue jobs){return new RecordingEditing(jdbc,access,mutations,revisions,changes,drafts,saving,jobs);}
    @Bean RecordingListing recordingListing(AccountAccess access,com.ksh321.songrecord.api.pagination.KeysetPages pages){return new RecordingListing(access,pages);}
    @Bean RecordingSaving recordingSaving(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,com.ksh321.songrecord.api.revision.RevisionChanges revisions,AccountChanges changes,RecordingDrafts drafts){return new RecordingSaving(jdbc,access,mutations,revisions,changes,drafts);}
    @Bean RecordingDrafts recordingDrafts(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,AccountChanges changes){return new RecordingDrafts(jdbc,access,mutations,guard,changes,Clock.systemUTC());}
    @Bean @Order(3) SecurityFilterChain recordingSecurity(HttpSecurity http)throws Exception{
        http.securityMatcher("/v1/recordings","/v1/recordings/**").csrf(c->c.disable())
            .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable())
            .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/v1/recordings").permitAll().requestMatchers(HttpMethod.POST,"/v1/recordings").permitAll().requestMatchers(HttpMethod.PATCH,"/v1/recordings/*","/v1/recordings/*/tier","/v1/recordings/*/song").permitAll().anyRequest().denyAll());
        return http.build();
    }
}
