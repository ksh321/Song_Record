package com.ksh321.songrecord.api.locking;

import com.ksh321.songrecord.api.auth.AccountAccess;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class LockConfiguration {
    @Bean StorageLocks storageLocks(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager){return new StorageLocks(jdbc,access,manager);}
}
