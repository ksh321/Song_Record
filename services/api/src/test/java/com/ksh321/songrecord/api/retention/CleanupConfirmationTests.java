package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class CleanupConfirmationTests {
 @org.junit.jupiter.api.Test void jdbcDateTimeTypesHaveTheSameUtcExpiry(){var time=java.time.Instant.parse("2026-10-09T03:00:00Z");org.assertj.core.api.Assertions.assertThat(CleanupConfirmations.instant(java.sql.Timestamp.from(time))).isEqualTo(time);org.assertj.core.api.Assertions.assertThat(CleanupConfirmations.instant(java.time.LocalDateTime.ofInstant(time,java.time.ZoneOffset.UTC))).isEqualTo(time);}

 @Test void opaqueTokenBindsOwnerGenerationHashRevisionAndExpiresWithoutDeletion(){var f=new RetentionCandidatesTests();f.setup();try{f.selectionSchema();var db=f.db;
 db.execute("CREATE TABLE storage_usage(user_id BINARY(16) PRIMARY KEY,used_bytes BIGINT DEFAULT 0)");
 db.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,current_recording_id BINARY(16),pending_recording_id BINARY(16))");
 db.execute("CREATE TABLE mutation_receipt(user_id BINARY(16),op_id BINARY(16),request_hash VARCHAR(64),response_status INT,response_body VARCHAR(20000),created_at TIMESTAMP(3),expires_at TIMESTAMP(3),PRIMARY KEY(user_id,op_id))");
 db.execute("CREATE TABLE cloud_cleanup(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16),generation BINARY(16),expected_sha256 VARCHAR(64),expected_cloud_revision BIGINT,confirmation_mode VARCHAR(32),confirmed_at TIMESTAMP(3),confirmation_expires_at TIMESTAMP(3),state VARCHAR(24),created_at TIMESTAMP(3),updated_at TIMESTAMP(3),completed_at TIMESTAMP(3))");
 CleanupConfirmationDatabaseChecks.verify(db);}finally{f.close();}}
}
