package com.ksh321.songrecord.api.ownership;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.auth.SessionService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;

@Configuration(proxyBeanMethods = false)
@Profile("!bootstrap")
public class OwnershipConfiguration {
    @Bean AccountAccess accountAccess(SessionService sessions) { return new AccountAccess(sessions); }
    @Bean OwnershipGuard ownershipGuard(JdbcTemplate jdbc, AccountAccess access) {
        return new OwnershipGuard(jdbc, access);
    }
}
