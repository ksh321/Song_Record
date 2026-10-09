package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadFailureTests {
 @Test void failedNewUploadPreservesPriorServerGenerationAndAccounting()throws Exception{var db=UploadFinalizationTests.database();try(var c=db.getDataSource().getConnection()){new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(c);UploadFailureDatabaseChecks.verify(db);}}
}
