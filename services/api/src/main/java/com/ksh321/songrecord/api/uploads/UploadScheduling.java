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
 private final JobRunner runner;private final UploadVerification verification;private final AudioValidator validator;private final UploadFinalization finalizer;
 public UploadScheduling(JobQueue jobs,UploadVerification verification,AudioValidator validator,UploadFinalization finalizer){runner=new JobRunner(jobs);this.verification=verification;this.validator=validator;this.finalizer=finalizer;}
 @Bean ThreadPoolTaskScheduler uploadScheduler(){var s=new ThreadPoolTaskScheduler();s.setPoolSize(1);s.setThreadNamePrefix("upload-");return s;}
 @Scheduled(fixedDelay=1000,initialDelay=1000,scheduler="uploadScheduler")
 public void tick(){try{runner.runOnce(JobQueue.Type.UPLOAD_VERIFY,lease->verification.prepare(lease,validator.then(finalizer)));}catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(UploadScheduling.class).warn("upload_worker_tick_failed");}}
}
