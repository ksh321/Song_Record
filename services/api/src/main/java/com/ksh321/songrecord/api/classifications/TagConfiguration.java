package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import com.ksh321.songrecord.api.revision.*;
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
public class TagConfiguration {
    @Bean TagService tagService(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,RevisionChanges revisions,AccountChanges changes,KeysetPages pages){return new TagService(jdbc,access,mutations,guard,revisions,changes,pages,Clock.systemUTC());}
    @Bean @Order(4) SecurityFilterChain tagSecurity(HttpSecurity http)throws Exception{
        http.securityMatcher("/v1/tags","/v1/tags/**").csrf(c->c.disable()).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable())
            .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/v1/tags").permitAll().requestMatchers(HttpMethod.POST,"/v1/tags","/v1/tags/*/archive").permitAll().requestMatchers(HttpMethod.PATCH,"/v1/tags/*").permitAll().anyRequest().denyAll());return http.build();
    }
}
