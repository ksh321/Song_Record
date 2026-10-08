package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class UploadConfiguration {
    @Bean UploadApproval uploadApproval(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,IdempotentMutations mutations){
        return new UploadApproval(db,access,manager,Clock.systemUTC(),mutations);
    }
}
