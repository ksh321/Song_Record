package com.ksh321.songrecord.api.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;

@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(name = "auth.kakao.enabled", havingValue = "true")
public class KakaoProofConfiguration {
    @Bean(destroyMethod = "close")
    KakaoHttpTokenInfoClient kakaoTokenInfoClient() { return new KakaoHttpTokenInfoClient(); }

    @Bean
    KakaoProofVerifier kakaoProofVerifier(@Value("${auth.kakao.app-id:0}") long appId,
                                        KakaoHttpTokenInfoClient client) {
        return new KakaoProofVerifier(appId, client);
    }

    @Configuration(proxyBeanMethods = false)
    @Profile("!bootstrap")
    @ConditionalOnProperty(name = "auth.kakao.enabled", havingValue = "true")
    static class IdentityConfiguration {
        @Bean
        AuthIdentityRepository authIdentityRepository(JdbcTemplate jdbc) {
            return new JdbcAuthIdentityRepository(jdbc);
        }

        @Bean
        KakaoIdentityLookup kakaoIdentityLookup(KakaoProofVerifier verifier, AuthIdentityRepository repository) {
            return new KakaoIdentityLookup(verifier, repository);
        }
    }
}
