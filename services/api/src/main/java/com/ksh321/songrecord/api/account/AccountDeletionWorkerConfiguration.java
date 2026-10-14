package com.ksh321.songrecord.api.account;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.scheduling.annotation.Scheduled;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.storage.R2Storage;
import java.time.Clock;
import java.nio.file.Path;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
@ConditionalOnProperty(name="songrecord.account-deletion.worker.enabled",havingValue="true")
public class AccountDeletionWorkerConfiguration {
 @Bean DeletionArtifacts deletionArtifacts(@Value("${songrecord.account-deletion.ledger-directory:}")String ledger,@Value("${songrecord.account-deletion.backup-directory:}")String backups,@Value("${songrecord.storage.environment}")String environment,org.springframework.beans.factory.ObjectProvider<com.ksh321.songrecord.api.operations.BackupDeletionFence> fences)throws Exception{var fence=fences.getIfAvailable();return fence==null?new PrivateDeletionArtifacts(Path.of(ledger),Path.of(backups),environment):new com.ksh321.songrecord.api.operations.BackupDeletionArtifacts(fence);}
 @Bean AccountDeletionWorker accountDeletionWorker(JdbcTemplate db,PlatformTransactionManager tx,JobQueue jobs,R2Storage storage,DeletionArtifacts artifacts){storage.finalWriterBucket();return new AccountDeletionWorker(db,tx,jobs,storage,artifacts,Clock.systemUTC());}
 @Bean Maintenance accountDeletionMaintenance(AccountDeletionWorker worker){return new Maintenance(worker);}
 static final class Maintenance {
  private final AccountDeletionWorker worker;Maintenance(AccountDeletionWorker worker){this.worker=worker;}
  @Scheduled(initialDelay=5000,fixedDelay=5000,scheduler="storageRequestScheduler") public void run(){try{worker.runOnce();worker.retireCompleted();}catch(RuntimeException unavailable){org.slf4j.LoggerFactory.getLogger(getClass()).error("Account deletion maintenance deferred; operator recovery required");}}
 }
}
