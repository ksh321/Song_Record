package com.ksh321.songrecord.api.retention;
import java.time.Clock;import com.ksh321.songrecord.api.jobs.JobQueue;import com.ksh321.songrecord.api.storage.R2Storage;import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.transaction.PlatformTransactionManager;import org.springframework.context.annotation.*;import org.springframework.scheduling.annotation.*;import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap") @EnableScheduling
@org.springframework.boot.autoconfigure.condition.ConditionalOnExpression("'${songrecord.storage.role:api}' == 'worker' && '${songrecord.cleanup.scheduling-enabled:true}' == 'true'")
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
public class CleanupScheduling {
 private final CleanupWorker worker;public CleanupScheduling(JdbcTemplate db,PlatformTransactionManager manager,com.ksh321.songrecord.api.auth.AccountAccess access,R2Storage objects){var queue=new JobQueue(db,access,manager,Clock.systemUTC(),java.time.Duration.ofMinutes(2),5);worker=new CleanupWorker(queue,new CleanupDeletion(db,manager,queue,objects,Clock.systemUTC()));}
 @Bean ThreadPoolTaskScheduler cleanupScheduler(){var s=new ThreadPoolTaskScheduler();s.setPoolSize(1);s.setThreadNamePrefix("cleanup-");return s;}
 @Scheduled(fixedDelay=1000,initialDelay=1000,scheduler="cleanupScheduler")public void tick(){try{worker.runOnce();}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(CleanupScheduling.class).warn("cleanup_worker_tick_failed");}}
}
