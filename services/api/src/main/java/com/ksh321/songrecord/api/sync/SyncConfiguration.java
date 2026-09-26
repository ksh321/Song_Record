package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class SyncConfiguration {
    @Bean AccountChanges accountChanges(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager) {
        return new AccountChanges(jdbc,access,manager,Clock.systemUTC());
    }
}
