package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.pagination.*;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.mock;
class PaginationConfigurationTests {
    ApplicationContextRunner runner(){return new ApplicationContextRunner().withUserConfiguration(PaginationConfiguration.class)
            .withInitializer(c->c.getEnvironment().setActiveProfiles("dev"))
            .withBean(JdbcTemplate.class,()->mock(JdbcTemplate.class)).withBean(AccountAccess.class,()->mock(AccountAccess.class))
            .withBean(PlatformTransactionManager.class,()->mock(PlatformTransactionManager.class));}
    @Test void missingOrMalformedKeyFailsLiveStartup(){
        runner().withPropertyValues("songrecord.pagination.key-base64=").run(c->assertThat(c).hasFailed());
        runner().withPropertyValues("songrecord.pagination.key-base64=bad").run(c->assertThat(c).hasFailed());
    }
    @Test void configuredKeyCreatesPager(){runner().withPropertyValues("songrecord.pagination.key-base64="+java.util.Base64.getEncoder().encodeToString(new byte[32])).run(c->assertThat(c).hasSingleBean(KeysetPages.class));}
    @Test void bootstrapNeedsNoCursorKey(){new ApplicationContextRunner().withUserConfiguration(PaginationConfiguration.class).withInitializer(c->c.getEnvironment().setActiveProfiles("bootstrap")).run(c->assertThat(c).doesNotHaveBean(PageCursor.class));}
}
