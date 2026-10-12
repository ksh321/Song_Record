package com.ksh321.songrecord.api.account;
import java.time.Clock;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.pagination.KeysetPages;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap") @EnableScheduling
public class StorageRequestConfiguration{
 @Bean StorageRequests storageRequests(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,KeysetPages pages){return new StorageRequests(db,access,mutations,pages,Clock.systemUTC());}
 @Bean(name="storageRequestScheduler") ThreadPoolTaskScheduler scheduler(){var s=new ThreadPoolTaskScheduler();s.setPoolSize(1);s.setThreadNamePrefix("storage-demand-");return s;}
 @Bean Expiry expiry(StorageRequests requests){return new Expiry(requests);}
 static final class Expiry{private final StorageRequests requests;Expiry(StorageRequests requests){this.requests=requests;}
  @Scheduled(fixedDelay=3600000,initialDelay=60000,scheduler="storageRequestScheduler") public void tick(){try{requests.pruneExpired();}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(Expiry.class).warn("storage_request_expiry_failed");}}
 }
}
