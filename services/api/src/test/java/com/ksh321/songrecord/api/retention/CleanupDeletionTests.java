package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;import org.springframework.jdbc.core.JdbcTemplate;
class CleanupDeletionTests {
 @Test void configuredWorkerStartsWithExistingDependenciesAndApiNeverStartsDeletion(){
  for(String role:new String[]{"api","worker"})try(var context=new org.springframework.context.annotation.AnnotationConfigApplicationContext()){
   context.setEnvironment(new org.springframework.mock.env.MockEnvironment().withProperty("songrecord.storage.enabled","true").withProperty("songrecord.storage.role",role));
   context.registerBean(JdbcTemplate.class,()->org.mockito.Mockito.mock(JdbcTemplate.class));context.registerBean(org.springframework.transaction.PlatformTransactionManager.class,()->org.mockito.Mockito.mock(org.springframework.transaction.PlatformTransactionManager.class));context.registerBean(com.ksh321.songrecord.api.auth.AccountAccess.class,()->org.mockito.Mockito.mock(com.ksh321.songrecord.api.auth.AccountAccess.class));context.registerBean(com.ksh321.songrecord.api.storage.R2Storage.class,()->org.mockito.Mockito.mock(com.ksh321.songrecord.api.storage.R2Storage.class));context.register(CleanupScheduling.class);context.refresh();org.assertj.core.api.Assertions.assertThat(context.containsBean("cleanupScheduler")).isEqualTo(role.equals("worker"));
  }
 }
 static void schema(JdbcTemplate db){db.execute("ALTER TABLE storage_usage ADD revision BIGINT DEFAULT 1");db.execute("ALTER TABLE storage_usage ADD updated_at TIMESTAMP");db.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,used_bytes BIGINT DEFAULT 0,revision BIGINT DEFAULT 1,updated_at TIMESTAMP)");db.update("INSERT INTO global_storage_usage(id) VALUES(1)");db.execute("CREATE TABLE deletion_ledger(id BINARY(16) PRIMARY KEY,user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),object_generation BINARY(16),revision BIGINT,purged_at TIMESTAMP,UNIQUE(user_id,entity_type,entity_id,object_generation),CHECK(revision>0))");}
 @Test void lostRepliesFailuresLeasesAndGenerationsNeverDebitEarly()throws Exception{CleanupAuthorizationTests.withFixture(db->{schema(db);CleanupDeletionDatabaseChecks.verify(db);});}
}
