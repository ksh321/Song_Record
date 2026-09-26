package com.ksh321.songrecord.api.auth;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class AuthHttpSecurityConfiguration {
    @Bean @Order(1)
    SecurityFilterChain authHttpSecurity(HttpSecurity http) throws Exception {
        // Mobile bearer-only endpoints; no cookies, HTTP Basic, form login, or server HTTP session.
        http.securityMatcher("/v1/auth/**")
                .csrf(csrf->csrf.disable())
                .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .requestCache(c->c.disable())
                .authorizeHttpRequests(a->a.requestMatchers(HttpMethod.POST,"/v1/auth/social","/v1/auth/refresh",
                        "/v1/auth/identities/reauth-challenges","/v1/auth/identities/link-challenges","/v1/auth/identities/link").permitAll()
                        // /me verifies the bearer and device through SessionService before returning anything.
                        .requestMatchers(HttpMethod.GET,"/v1/auth/me","/v1/auth/identities").permitAll().anyRequest().denyAll());
        return http.build();
    }
}
