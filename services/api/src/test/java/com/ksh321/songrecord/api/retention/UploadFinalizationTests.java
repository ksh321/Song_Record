package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadFinalizationTests {
 @Test void immutableBytesAndAtomicFencedAccounting()throws Exception{var db=UploadApprovalTests.database();try(var c=db.getDataSource().getConnection()){new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(c);UploadFinalizationDatabaseChecks.verify(db);}}
}
