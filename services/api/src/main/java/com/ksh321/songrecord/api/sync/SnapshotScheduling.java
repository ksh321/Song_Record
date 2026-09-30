package com.ksh321.songrecord.api.sync;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/** Bounded dedicated worker and five-minute maintenance; leases survive process shutdown. */
@Configuration(proxyBeanMethods=false)
@Profile("!bootstrap")
@EnableScheduling
@ConditionalOnProperty(name="songrecord.snapshots.scheduling-enabled",havingValue="true",matchIfMissing=true)
public class SnapshotScheduling {
    private static final org.slf4j.Logger LOG=org.slf4j.LoggerFactory.getLogger(SnapshotScheduling.class);
    private final SnapshotWorker worker;
    private final SnapshotCleanup cleanup;
    public SnapshotScheduling(SnapshotWorker worker,SnapshotCleanup cleanup){this.worker=worker;this.cleanup=cleanup;}
    @Bean ThreadPoolTaskScheduler snapshotScheduler(){
        var scheduler=new ThreadPoolTaskScheduler();scheduler.setPoolSize(2);scheduler.setThreadNamePrefix("snapshot-");
        return scheduler;
    }
    @Scheduled(fixedDelay=1000,initialDelay=1000,scheduler="snapshotScheduler")
    public void build(){try{worker.runOnce();}catch(RuntimeException e){LOG.warn("snapshot_worker_tick_failed type={}",e.getClass().getSimpleName());}}
    @Scheduled(fixedDelay=300000,initialDelay=300000,scheduler="snapshotScheduler")
    public void clean(){try{cleanup.runOnce();}catch(RuntimeException e){LOG.warn("snapshot_cleanup_tick_failed type={}",e.getClass().getSimpleName());}}
}
