package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.storage.R2Storage;
import java.time.Clock;
import org.springframework.context.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
@Configuration(proxyBeanMethods=false) @Profile("!bootstrap")
@ConditionalOnProperty(name="songrecord.storage.enabled",havingValue="true")
public class UploadWorkerConfiguration {
    @Bean @ConditionalOnProperty(name="songrecord.storage.role",havingValue="worker")
    UploadVerification uploadVerification(JdbcTemplate db,R2Storage storage){return new UploadVerification(db,storage::openTemporary,Clock.systemUTC());}
    @Bean @ConditionalOnProperty(name="songrecord.storage.role",havingValue="worker")
    UploadFinalization uploadFinalization(JdbcTemplate db,R2Storage storage){return new UploadFinalization(db,new UploadFinalObjects(){public void ensure(com.ksh321.songrecord.api.storage.StorageObjectKeys.Final key,java.nio.ByteBuffer bytes,String hash)throws Exception{storage.ensureFinal(key,bytes,hash);}public java.util.Optional<java.nio.ByteBuffer> read(com.ksh321.songrecord.api.storage.StorageObjectKeys.Final key)throws Exception{return storage.readFinal(key);}},Clock.systemUTC());}
    @Bean @ConditionalOnProperty(name="songrecord.storage.role",havingValue="worker")
    UploadInventory uploadInventory(JdbcTemplate db,R2Storage storage,org.springframework.transaction.PlatformTransactionManager manager){return new UploadInventory(db,manager,storage,Clock.systemUTC());}
    @Bean @ConditionalOnProperty(name="songrecord.storage.role",havingValue="worker")
    AudioValidator audioValidator(org.springframework.core.env.Environment environment){return new AudioValidator(environment.getProperty("songrecord.upload.ffmpeg","ffmpeg"),environment.getProperty("songrecord.upload.ffprobe","ffprobe"),environment.getProperty("songrecord.upload.python",System.getProperty("os.name").startsWith("Windows")?"python":"python3"));}
}
