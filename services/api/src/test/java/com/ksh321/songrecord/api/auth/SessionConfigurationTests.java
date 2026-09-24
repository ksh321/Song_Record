package com.ksh321.songrecord.api.auth;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.convert.ApplicationConversionService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class SessionConfigurationTests {
    private final ApplicationContextRunner runner=new ApplicationContextRunner()
            .withUserConfiguration(SessionConfiguration.class)
            .withInitializer(c->c.getBeanFactory().setConversionService(ApplicationConversionService.getSharedInstance()));
    @Test void bootstrapDoesNotRequireDatabase() {
        runner.withInitializer(c->c.getEnvironment().setActiveProfiles("bootstrap"))
                .run(c->assertThat(c).doesNotHaveBean(SessionService.class));
    }
    @Test void devConfiguresDefaultLifetimes() {
        database().run(c->assertThat(c).hasSingleBean(SessionService.class));
    }
    @Test void invalidConfigurationFailsStartup() {
        database().withPropertyValues("auth.session.access-ttl=PT0S").run(c->assertThat(c).hasFailed());
    }
    private ApplicationContextRunner database() {
        return runner.withInitializer(c->c.getEnvironment().setActiveProfiles("dev"))
                .withBean(JdbcTemplate.class,()->mock(JdbcTemplate.class))
                .withBean(PlatformTransactionManager.class,()->mock(PlatformTransactionManager.class));
    }
}
