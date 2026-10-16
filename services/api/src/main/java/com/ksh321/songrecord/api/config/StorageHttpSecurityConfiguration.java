package com.ksh321.songrecord.api.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/** Dispatch only the existing storage contract to its device-bound AccountAccess checks. */
@Configuration(proxyBeanMethods = false)
@Profile("!bootstrap")
public class StorageHttpSecurityConfiguration {
    // Must precede RecordingConfiguration's /v1/recordings/** chain at order 3.
    @Bean @Order(2)
    SecurityFilterChain storageHttpSecurity(HttpSecurity http) throws Exception {
        return http.securityMatcher(
                    "/v1/storage", "/v1/storage/**", "/v1/pins", "/v1/pins/**",
                    "/v1/uploads/**", "/v1/recordings/*/retention",
                    "/v1/recordings/*/preservation-url", "/v1/recordings/*/uploads",
                    "/v1/recordings/*/playback-url")
                // These endpoints authenticate explicit bearer + device headers, never cookies.
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .requestCache(cache -> cache.disable())
                .authorizeHttpRequests(authorize -> authorize
                    .requestMatchers(HttpMethod.GET, "/v1/storage", "/v1/pins",
                            "/v1/storage/requests/me", "/v1/storage/requests/*",
                            "/v1/recordings/*/retention", "/v1/recordings/*/preservation-url").permitAll()
                    .requestMatchers(HttpMethod.POST, "/v1/pins", "/v1/pins/*/replacement",
                            "/v1/pins/*/replacement/cancel", "/v1/storage/requests",
                            "/v1/storage/cleanup-previews", "/v1/storage/cleanup-confirmations",
                            "/v1/recordings/*/uploads", "/v1/uploads/*/renew-url",
                            "/v1/uploads/*/complete", "/v1/uploads/*/cancel",
                            "/v1/recordings/*/playback-url").permitAll()
                    .requestMatchers(HttpMethod.DELETE, "/v1/pins/*").permitAll()
                    .anyRequest().denyAll())
                .build();
    }
}
