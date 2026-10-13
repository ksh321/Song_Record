package com.ksh321.songrecord.api.auth;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods = false)
@Profile("!bootstrap")
public class AccountRegistrationConfiguration {
    @Bean
    AccountRegistrationService accountRegistrationService(JdbcTemplate jdbc, PlatformTransactionManager manager, org.springframework.core.env.Environment environment) {
        return new AccountRegistrationService(jdbc, manager, Clock.systemUTC(), environment.acceptsProfiles(org.springframework.core.env.Profiles.of("staging","prod"))?com.ksh321.songrecord.api.operations.OperationsPolicy.from(environment):null);
    }
}
