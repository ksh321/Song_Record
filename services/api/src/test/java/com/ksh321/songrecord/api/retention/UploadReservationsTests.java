package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadReservationsTests {
    @Test void capacityBoundariesRacesReplayRollbackAndOverflow()throws Exception {
        UploadReservationDatabaseChecks.verify(database());
    }
    @Test void configuredReservationCapsKeepExistingAttemptsAndData() {
        var db=database();var owner=RetentionCandidateDatabaseChecks.account(db);var device=RetentionCandidateDatabaseChecks.device(db,owner);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(owner));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(owner));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(owner));
        var account=org.mockito.Mockito.mock(com.ksh321.songrecord.api.auth.AccountAccess.Account.class);var access=org.mockito.Mockito.mock(com.ksh321.songrecord.api.auth.AccountAccess.class);org.mockito.Mockito.when(access.revalidate(account)).thenReturn(new com.ksh321.songrecord.api.auth.SessionService.Principal(owner,device,java.util.UUID.randomUUID()));
        var policy=new com.ksh321.songrecord.api.operations.OperationsPolicy(20,10,1000000000L,5,100,1,1,2,1,5);
        var service=new com.ksh321.songrecord.api.uploads.UploadReservations(db,access,new org.springframework.jdbc.datasource.DataSourceTransactionManager(db.getDataSource()),java.time.Clock.systemUTC(),policy);
        var r1=RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");var r2=RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");
        var request=new com.ksh321.songrecord.api.uploads.UploadReservations.Request(r1,3,"a".repeat(64),1);var reserved=service.reserve(account,request);
        db.update("UPDATE recording_upload SET active_slot=1"); // Preserved second slot from an earlier two-slot policy.
        UploadApprovalDatabaseChecks.assertCode(()->service.reserve(account,new com.ksh321.songrecord.api.uploads.UploadReservations.Request(r2,1,"a".repeat(64),1)),"UPLOAD_CONCURRENCY_LIMIT");
        db.update("UPDATE global_storage_usage SET temp_observed_bytes=2");UploadApprovalDatabaseChecks.assertCode(()->service.reserve(account,new com.ksh321.songrecord.api.uploads.UploadReservations.Request(r2,1,"a".repeat(64),1)),"UPLOAD_BUDGET_LOCKED");
        org.assertj.core.api.Assertions.assertThat(service.reserve(account,request)).isEqualTo(reserved);
        org.assertj.core.api.Assertions.assertThat(db.queryForObject("SELECT reserved_bytes FROM global_storage_usage",Long.class)).isEqualTo(3);
        org.assertj.core.api.Assertions.assertThat(db.queryForObject("SELECT COUNT(*) FROM recording",Integer.class)).isEqualTo(2);
    }
    static org.springframework.jdbc.core.JdbcTemplate database(){
        var f=new RetentionCandidatesTests();f.setup();var db=f.db;
        db.execute("CREATE TABLE user_sync_state(user_id BINARY(16) PRIMARY KEY)");
        db.execute("CREATE TABLE user_entitlement(user_id BINARY(16) PRIMARY KEY,quota_bytes BIGINT DEFAULT 1000000000)");
        db.execute("CREATE TABLE storage_usage(user_id BINARY(16) PRIMARY KEY,used_bytes BIGINT DEFAULT 0 CHECK(used_bytes>=0),reserved_bytes BIGINT DEFAULT 0 CHECK(reserved_bytes>=0),revision BIGINT DEFAULT 1,updated_at TIMESTAMP)");
        db.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,used_bytes BIGINT DEFAULT 0,reserved_bytes BIGINT DEFAULT 0,primary_quota_bytes BIGINT DEFAULT 20000000000,upload_locked BOOLEAN DEFAULT FALSE,temp_observed_bytes BIGINT DEFAULT 0,reconciliation_locked BOOLEAN DEFAULT FALSE,final_observed_bytes BIGINT DEFAULT 0,reconciliation_issue_count BIGINT DEFAULT 0,reconciliation_at TIMESTAMP,revision BIGINT DEFAULT 1,updated_at TIMESTAMP)");
        db.execute("INSERT INTO global_storage_usage(id) VALUES(1)");
        db.execute("CREATE TABLE recording_upload(id BINARY(16) PRIMARY KEY,user_id BINARY(16),recording_id BINARY(16),state VARCHAR(20),active_slot INT,expected_size BIGINT CHECK(expected_size BETWEEN 1 AND 6291456),expected_sha256 VARCHAR(64),temp_key VARCHAR(512) UNIQUE,final_key VARCHAR(512) UNIQUE,policy_revision BIGINT,pin_operation_id BINARY(16),reservation_released_at TIMESTAMP,error_code VARCHAR(64),expires_at TIMESTAMP(3),created_at TIMESTAMP(3),updated_at TIMESTAMP(3),UNIQUE(user_id,active_slot))");
        return db;
    }
}
