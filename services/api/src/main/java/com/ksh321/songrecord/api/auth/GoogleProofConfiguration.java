package com.ksh321.songrecord.api.auth;

import java.net.URI;
import java.time.Clock;

import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.jwk.source.JWKSourceBuilder;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jose.util.DefaultResourceRetriever;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(name = "auth.google.enabled", havingValue = "true")
public class GoogleProofConfiguration {
    @Bean(destroyMethod = "close")
    JWKSource<SecurityContext> googleProofKeys() throws java.net.MalformedURLException {
        return JWKSourceBuilder.<SecurityContext>create(
                URI.create("https://www.googleapis.com/oauth2/v3/certs").toURL(),
                new DefaultResourceRetriever(2000, 3000, 65_536))
                .cache(300_000, 5000).refreshAheadCache(false).retrying(false).build();
    }

    @Bean
    GoogleProofVerifier googleProofVerifier(
            @Value("${auth.google.server-client-id:}") String audience,
            JWKSource<SecurityContext> googleProofKeys) {
        return new GoogleProofVerifier(audience, googleProofKeys, Clock.systemUTC());
    }
}
