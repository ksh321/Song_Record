package com.ksh321.songrecord.api.revision;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class RevisionConfiguration {
    @Bean CreationGuard creationGuard(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager) {
        return new CreationGuard(jdbc,access,manager);
    }
    @Bean RevisionChanges revisionChanges(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager) {
        return new RevisionChanges(jdbc,access,manager,Clock.systemUTC());
    }
}
