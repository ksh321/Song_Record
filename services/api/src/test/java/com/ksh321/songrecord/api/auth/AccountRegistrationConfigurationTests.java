package com.ksh321.songrecord.api.auth;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class AccountRegistrationConfigurationTests {
    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(AccountRegistrationConfiguration.class);
    @Test void bootstrapNeedsNoDatabase() {
        runner.withInitializer(c -> c.getEnvironment().setActiveProfiles("bootstrap"))
                .run(c -> assertThat(c).doesNotHaveBean(AccountRegistrationService.class));
    }
    @Test void devWiresRegistration() {
        runner.withInitializer(c -> c.getEnvironment().setActiveProfiles("dev"))
                .withBean(JdbcTemplate.class, () -> mock(JdbcTemplate.class))
                .withBean(PlatformTransactionManager.class, () -> mock(PlatformTransactionManager.class))
                .run(c -> assertThat(c).hasSingleBean(AccountRegistrationService.class));
    }
}
