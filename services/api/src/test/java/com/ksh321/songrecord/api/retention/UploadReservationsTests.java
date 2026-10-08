package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadReservationsTests {
    @Test void capacityBoundariesRacesReplayRollbackAndOverflow()throws Exception {
        var f=new RetentionCandidatesTests();f.setup();var db=f.db;
        db.execute("CREATE TABLE user_sync_state(user_id BINARY(16) PRIMARY KEY)");
        db.execute("CREATE TABLE user_entitlement(user_id BINARY(16) PRIMARY KEY,quota_bytes BIGINT DEFAULT 1000000000)");
        db.execute("CREATE TABLE storage_usage(user_id BINARY(16) PRIMARY KEY,used_bytes BIGINT DEFAULT 0 CHECK(used_bytes>=0),reserved_bytes BIGINT DEFAULT 0 CHECK(reserved_bytes>=0),revision BIGINT DEFAULT 1,updated_at TIMESTAMP)");
        db.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,used_bytes BIGINT DEFAULT 0,reserved_bytes BIGINT DEFAULT 0,primary_quota_bytes BIGINT DEFAULT 20000000000,upload_locked BOOLEAN DEFAULT FALSE,revision BIGINT DEFAULT 1,updated_at TIMESTAMP)");
        db.execute("INSERT INTO global_storage_usage(id) VALUES(1)");
        db.execute("CREATE TABLE recording_upload(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16),state VARCHAR(20),active_slot INT,expected_size BIGINT CHECK(expected_size BETWEEN 1 AND 6291456),expected_sha256 VARCHAR(64),temp_key VARCHAR(512) UNIQUE,final_key VARCHAR(512) UNIQUE,policy_revision BIGINT,expires_at TIMESTAMP(3),created_at TIMESTAMP(3),updated_at TIMESTAMP(3),UNIQUE(user_id,active_slot))");
        UploadReservationDatabaseChecks.verify(db);
    }
}
