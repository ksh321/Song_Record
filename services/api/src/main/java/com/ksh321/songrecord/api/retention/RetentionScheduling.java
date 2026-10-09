package com.ksh321.songrecord.api.retention;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.jobs.JobQueue;
import java.time.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
@EnableScheduling
@ConditionalOnProperty(name="songrecord.retention.scheduling-enabled",havingValue="true",matchIfMissing=true)
public class RetentionScheduling {
    private final RetentionWorker worker;private final RetentionSelectionStore store;private final CleanupCandidates cleanup;private final CleanupAuthorizations authorizations;private final PinTransitions pins;
    public RetentionScheduling(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager,RetentionSelectionStore store){
        this.store=store;this.pins=new PinTransitions(jdbc,manager);this.cleanup=new CleanupCandidates(jdbc,manager);var queue=new JobQueue(jdbc,access,manager,Clock.systemUTC(),Duration.ofMinutes(2),5);worker=new RetentionWorker(queue,store);authorizations=new CleanupAuthorizations(jdbc,manager,queue,Clock.systemUTC());
    }
    @Scheduled(fixedDelay=60000,initialDelay=60000,scheduler="retentionScheduler")
    public void refresh(){try{pins.refresh();store.refreshReplacementHolds();cleanup.refresh();authorizations.refresh();}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(RetentionScheduling.class).warn("retention_reasons_refresh_failed");}}
    @Bean ThreadPoolTaskScheduler retentionScheduler(){var scheduler=new ThreadPoolTaskScheduler();scheduler.setPoolSize(1);scheduler.setThreadNamePrefix("retention-");return scheduler;}
    @Scheduled(fixedDelay=1000,initialDelay=1000,scheduler="retentionScheduler")
    public void tick(){try{worker.runOnce();}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(RetentionScheduling.class).warn("retention_worker_tick_failed type={}",e.getClass().getSimpleName());}}
}
