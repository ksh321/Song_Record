package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
class UploadCompletionTests {
    @Test void completionReplayIsolationAndBoundedLeaseOwnedBytes()throws Exception{
        var db=UploadApprovalTests.database();
        try(var keeper=db.getDataSource().getConnection()){
            new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(keeper);
            UploadCompletionDatabaseChecks.verify(db);
        }
    }

    @Test void byteStageIsRegisteredOnlyForEnabledWorkerRole(){
        for(String role:java.util.List.of("api","worker")){
            try(var context=new org.springframework.context.annotation.AnnotationConfigApplicationContext()){
                context.setEnvironment(new org.springframework.mock.env.MockEnvironment().withProperty("songrecord.storage.enabled","true").withProperty("songrecord.storage.role",role));
                context.registerBean(org.springframework.jdbc.core.JdbcTemplate.class,()->org.mockito.Mockito.mock(org.springframework.jdbc.core.JdbcTemplate.class));
                context.registerBean(com.ksh321.songrecord.api.storage.R2Storage.class,()->org.mockito.Mockito.mock(com.ksh321.songrecord.api.storage.R2Storage.class));
                context.register(com.ksh321.songrecord.api.uploads.UploadWorkerConfiguration.class);context.refresh();
                org.assertj.core.api.Assertions.assertThat(context.getBeansOfType(com.ksh321.songrecord.api.uploads.UploadVerification.class).size()).isEqualTo(role.equals("worker")?1:0);
            }
        }
    }
}
