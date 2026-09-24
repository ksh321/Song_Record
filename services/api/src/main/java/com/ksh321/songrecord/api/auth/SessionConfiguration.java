package com.ksh321.songrecord.api.auth;

import java.time.Clock;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class SessionConfiguration {
    @Bean
    SessionService sessionService(JdbcTemplate jdbc, PlatformTransactionManager manager,
            @Value("${auth.session.access-ttl:PT15M}") Duration accessTtl,
            @Value("${auth.session.refresh-ttl:P30D}") Duration refreshTtl) {
        return new SessionService(jdbc,manager,Clock.systemUTC(),accessTtl,refreshTtl);
    }
}
