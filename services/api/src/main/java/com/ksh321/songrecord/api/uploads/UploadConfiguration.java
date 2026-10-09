package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
public class UploadConfiguration {
    @Bean @org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
    UploadUrls uploadUrls(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,IdempotentMutations mutations,UploadApproval approval,UploadPutSigner signer){
        return new UploadUrls(db,access,manager,mutations,approval,signer,Clock.systemUTC());
    }
    @Bean UploadRecovery uploadRecovery(JdbcTemplate db,PlatformTransactionManager manager){return new UploadRecovery(db,manager,Clock.systemUTC());}
    @Bean UploadCompletion uploadCompletion(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,IdempotentMutations mutations,com.ksh321.songrecord.api.jobs.JobQueue jobs){
        return new UploadCompletion(db,access,manager,mutations,jobs,Clock.systemUTC());
    }
    @Bean UploadApproval uploadApproval(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,IdempotentMutations mutations){
        return new UploadApproval(db,access,manager,Clock.systemUTC(),mutations);
    }
}
