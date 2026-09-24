package com.ksh321.songrecord.api.auth;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class KakaoProofConfigurationTests {
    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(KakaoProofConfiguration.class)
            .withInitializer(context -> context.getEnvironment().setActiveProfiles("bootstrap"));
    @Test void disabledByDefault() {
        runner.run(context -> assertThat(context).doesNotHaveBean(KakaoProofVerifier.class));
    }
    @Test void missingAppFailsStartup() {
        runner.withPropertyValues("auth.kakao.enabled=true").run(context -> assertThat(context).hasFailed());
    }
    @Test void bootstrapDoesNotNeedDatabaseOrNetwork() {
        runner.withPropertyValues("auth.kakao.enabled=true", "auth.kakao.app-id=1586938").run(context -> {
            assertThat(context).hasSingleBean(KakaoProofVerifier.class);
            assertThat(context).doesNotHaveBean(KakaoIdentityLookup.class);
        });
    }
    @Test void devWiresDatabaseLookup() {
        runner.withInitializer(context -> context.getEnvironment().setActiveProfiles("dev"))
                .withBean(JdbcTemplate.class, () -> mock(JdbcTemplate.class))
                .withPropertyValues("auth.kakao.enabled=true", "auth.kakao.app-id=1586938").run(context -> {
                    assertThat(context).hasSingleBean(KakaoIdentityLookup.class);
                    assertThat(context).hasSingleBean(AuthIdentityRepository.class);
                });
    }
}
