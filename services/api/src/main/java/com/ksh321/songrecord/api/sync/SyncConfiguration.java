package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.time.Clock;
import javax.sql.DataSource;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
public class SyncConfiguration {
    @Bean ChangeReadView changeReadView(DataSource source,AccountAccess access){return new ChangeReadView(source,access,Clock.systemUTC());}
    @Bean ChangeQueries changeQueries(AccountAccess access,ChangeReadView view){return new ChangeQueries(access,view);}
    @Bean AccountChanges accountChanges(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager) {
        return new AccountChanges(jdbc,access,manager,Clock.systemUTC());
    }
}
