package com.ksh321.songrecord.api.sync;

import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class ChangeHttpSecurityConfiguration {
    @Bean @Order(8) SecurityFilterChain changeSecurity(HttpSecurity http)throws Exception {
        // Only this GET is routed to AccountAccess authentication. All other methods remain denied.
        http.securityMatcher("/v1/sync/changes","/v1/sync/changes/**").csrf(c->c.disable())
            .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS)).requestCache(c->c.disable())
            .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.GET,"/v1/sync/changes").permitAll().anyRequest().denyAll());
        return http.build();
    }
}
