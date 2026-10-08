package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadApprovalTests {
    @Test void eligibilityDuplicateConcurrencyDailyAndRollingMinuteLimits()throws Exception{
        var db=UploadReservationsTests.database();
        db.execute("ALTER TABLE song ADD representative_recording_id BINARY(16)");
        db.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,current_recording_id BINARY(16),pending_recording_id BINARY(16),operation_id BINARY(16),requested_at TIMESTAMP,PRIMARY KEY(user_id,slot_no))");
        db.execute("CREATE TABLE cloud_hold(user_id BINARY(16),recording_id BINARY(16))");
        db.execute("CREATE TABLE recording_asset(user_id BINARY(16),recording_id BINARY(16),cloud_state VARCHAR(20),cloud_revision BIGINT,verified_size BIGINT,sha256 VARCHAR(64),generation BINARY(16),object_key VARCHAR(512),stored_at TIMESTAMP)");
        db.execute("CREATE TABLE upload_approval_daily(user_id BINARY(16),utc_day DATE,approved_bytes BIGINT CHECK(approved_bytes BETWEEN 0 AND 104857600),PRIMARY KEY(user_id,utc_day))");
        db.execute("CREATE TABLE upload_url_issue(user_id BINARY(16),id BINARY(16),issued_at TIMESTAMP(3),PRIMARY KEY(user_id,id))");
        db.execute("CREATE TABLE mutation_receipt(user_id BINARY(16),op_id BINARY(16),request_hash VARCHAR(64),response_status INT,response_body VARCHAR(20000),created_at TIMESTAMP(3),expires_at TIMESTAMP(3),PRIMARY KEY(user_id,op_id))");
        UploadApprovalDatabaseChecks.verify(db);
    }
}
