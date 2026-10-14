package com.ksh321.songrecord.api.operations;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.boot.sql.init.dependency.DependsOnDatabaseInitialization;
import org.springframework.beans.factory.InitializingBean;
import com.ksh321.songrecord.api.storage.R2Storage;
import java.time.Clock;
@Configuration(proxyBeanMethods=false) @Profile({"staging","prod"})
@org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
public class BackupFenceConfiguration {
 @Bean BackupDeletionFence backupDeletionFence(JdbcTemplate db){return new BackupDeletionFence(db,Clock.systemUTC(),true);}
 @Bean @DependsOnDatabaseInitialization InitializingBean backupStorageFence(R2Storage storage,BackupDeletionFence fence){return ()->storage.backupFence(fence);}
}
