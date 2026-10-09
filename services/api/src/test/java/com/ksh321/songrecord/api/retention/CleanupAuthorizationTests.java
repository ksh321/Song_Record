package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;import org.springframework.core.io.ClassPathResource;import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
class CleanupAuthorizationTests {
 @Test void lockedDecisionsPreserveEarlierPinsAndRejectLaterPins()throws Exception{var f=new RetentionCandidatesTests();f.setup();try{f.selectionSchema();var db=f.db;
 db.execute("ALTER TABLE user_sync_state ADD last_change_seq BIGINT DEFAULT 0");db.execute("ALTER TABLE user_sync_state ADD updated_at TIMESTAMP");db.execute("ALTER TABLE recording_asset ADD blocked_reason VARCHAR(32)");db.execute("ALTER TABLE recording_asset ADD created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP");
 db.execute("CREATE TABLE user_entitlement(user_id BINARY(16) PRIMARY KEY,pinned_limit INT DEFAULT 10,quota_bytes BIGINT DEFAULT 1073741824,revision BIGINT DEFAULT 1)");db.execute("CREATE TABLE storage_usage(user_id BINARY(16) PRIMARY KEY,used_bytes BIGINT DEFAULT 0)");
 db.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,current_recording_id BINARY(16),pending_recording_id BINARY(16),revision BIGINT,operation_id BINARY(16),requested_at TIMESTAMP,updated_at TIMESTAMP,PRIMARY KEY(user_id,slot_no))");
 db.execute("CREATE TABLE mutation_receipt(user_id BINARY(16),op_id BINARY(16),request_hash VARCHAR(64),response_status INT,response_body VARCHAR(20000),created_at TIMESTAMP(3),expires_at TIMESTAMP(3),PRIMARY KEY(user_id,op_id))");
 db.execute("CREATE TABLE cloud_cleanup(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16),generation BINARY(16),expected_sha256 VARCHAR(64),expected_cloud_revision BIGINT,confirmation_mode VARCHAR(32),confirmed_at TIMESTAMP(3),confirmation_expires_at TIMESTAMP(3),state VARCHAR(24),created_at TIMESTAMP(3),updated_at TIMESTAMP(3),completed_at TIMESTAMP(3),error_code VARCHAR(64),lease_until TIMESTAMP(3))");
 db.execute("CREATE TABLE change_log(user_id BINARY(16),change_seq BIGINT,entity_type VARCHAR(64),entity_id BINARY(16),revision BIGINT,operation VARCHAR(16),payload VARCHAR(20000),created_at TIMESTAMP,expires_at TIMESTAMP,PRIMARY KEY(user_id,change_seq))");try(var keeper=db.getDataSource().getConnection()){new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(keeper);CleanupAuthorizationDatabaseChecks.verify(db);}
 }finally{f.close();}}
}
