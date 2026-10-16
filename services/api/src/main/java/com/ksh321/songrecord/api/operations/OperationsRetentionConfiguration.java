package com.ksh321.songrecord.api.operations;

import java.time.Instant;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.scheduling.annotation.Scheduled;

@Configuration(proxyBeanMethods=false) @Profile({"staging","prod"})
@ConditionalOnProperty(name="songrecord.operations.retention.enabled",havingValue="true")
public class OperationsRetentionConfiguration {
 @Bean OperationsRetention operationsRetention(JdbcTemplate db,PlatformTransactionManager manager,@Value("${songrecord.storage.role:}")String role){
  if(!"worker".equals(role))throw new IllegalArgumentException("Observation retention requires worker role");
  return new OperationsRetention(db,manager,500);
 }
 @Bean RetentionTick operationsRetentionTick(OperationsRetention retention){return new RetentionTick(retention);}
 static final class RetentionTick {
  private final OperationsRetention retention;RetentionTick(OperationsRetention retention){this.retention=retention;}
  @Scheduled(initialDelay=60000,fixedDelay=60000,scheduler="storageRequestScheduler") public void prune(){
   try{int count=retention.prune(Instant.now());org.slf4j.LoggerFactory.getLogger(getClass()).info("operations_retention_completed removed={} days=30",count);}
   catch(RuntimeException error){org.slf4j.LoggerFactory.getLogger(getClass()).error("operations_retention_failed; operator recovery required");}
  }
 }
}
