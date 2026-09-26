package com.ksh321.songrecord.api.idempotency;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods = false)
@Profile("!bootstrap")
public class IdempotencyConfiguration {
    @Bean IdempotentMutations idempotentMutations(JdbcTemplate jdbc, AccountAccess access,
            PlatformTransactionManager manager) {
        return new IdempotentMutations(jdbc, access, manager, Clock.systemUTC());
    }
}
