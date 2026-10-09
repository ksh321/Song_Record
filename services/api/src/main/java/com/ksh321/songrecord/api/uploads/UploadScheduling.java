package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.jobs.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.*;
import org.springframework.scheduling.annotation.*;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap") @EnableScheduling
@org.springframework.boot.autoconfigure.condition.ConditionalOnExpression("\'${songrecord.storage.role:api}\' == \'worker\'")
@ConditionalOnProperty(name={"songrecord.storage.enabled","songrecord.upload.scheduling-enabled"},havingValue="true")
public class UploadScheduling {
 private final UploadWorker worker;private final UploadRecovery recovery;private final com.ksh321.songrecord.api.storage.R2Storage storage;
 public UploadScheduling(JobQueue jobs,UploadVerification verification,AudioValidator validator,UploadFinalization finalizer,UploadRecovery recovery,com.ksh321.songrecord.api.storage.R2Storage storage){this.recovery=recovery;this.storage=storage;worker=new UploadWorker(jobs,verification,validator,finalizer,recovery);}
 @Bean ThreadPoolTaskScheduler uploadScheduler(){var s=new ThreadPoolTaskScheduler();s.setPoolSize(2);s.setThreadNamePrefix("upload-");return s;}
 @Scheduled(fixedDelay=1000,initialDelay=1000,scheduler="uploadScheduler")
 public void tick(){try{worker.runOnce();}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(UploadScheduling.class).warn("upload_worker_tick_failed");}}
 @Scheduled(fixedDelay=60000,initialDelay=60000,scheduler="uploadScheduler")
 public void clean(){try{recovery.cleanup(storage);}catch(Exception e){org.slf4j.LoggerFactory.getLogger(UploadScheduling.class).warn("upload_cleanup_tick_failed");}}
}
