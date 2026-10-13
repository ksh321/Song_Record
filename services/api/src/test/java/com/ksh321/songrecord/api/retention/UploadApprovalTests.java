package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadApprovalTests {
    @Test void eligibilityDuplicateConcurrencyDailyAndRollingMinuteLimits()throws Exception{
        UploadApprovalDatabaseChecks.verify(database());
    }
    @Test void configuredDailyAndIssuanceLimitsResetAtUtcBoundaryWithoutDoubleCharging() {
        var db=database();var owner=RetentionCandidateDatabaseChecks.account(db);var device=RetentionCandidateDatabaseChecks.device(db,owner);var ownerBytes=com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(owner);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",ownerBytes);db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",ownerBytes);db.update("INSERT INTO storage_usage(user_id) VALUES(?)",ownerBytes);
        var access=org.mockito.Mockito.mock(com.ksh321.songrecord.api.auth.AccountAccess.class);var account=org.mockito.Mockito.mock(com.ksh321.songrecord.api.auth.AccountAccess.Account.class);org.mockito.Mockito.when(access.revalidate(account)).thenReturn(new com.ksh321.songrecord.api.auth.SessionService.Principal(owner,device,java.util.UUID.randomUUID()));
        var manager=new org.springframework.jdbc.datasource.DataSourceTransactionManager(db.getDataSource());var clock=new UploadApprovalDatabaseChecks.MutableClock();var policy=new com.ksh321.songrecord.api.operations.OperationsPolicy(20,10,1000000000L,20000000000L,6291456,1,2,536870912L,2,60);
        var service=new com.ksh321.songrecord.api.uploads.UploadApproval(db,access,manager,clock,new com.ksh321.songrecord.api.idempotency.IdempotentMutations(db,access,manager,clock),policy);
        var r1=RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");var r2=RetentionCandidateDatabaseChecks.recording(db,owner,device,null,true,true,"VALIDATED");
        int slot=0;for(var id:java.util.List.of(r1,r2))db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id,operation_id,requested_at) VALUES(?,?,?,?,CURRENT_TIMESTAMP)",ownerBytes,++slot,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(id),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(java.util.UUID.randomUUID()));
        var first=service.approve(account,r1,6291456,"a".repeat(64));org.assertj.core.api.Assertions.assertThat(service.approve(account,r1,6291456,"a".repeat(64))).isEqualTo(first);
        UploadApprovalDatabaseChecks.assertCode(()->service.approve(account,r2,6291456,"a".repeat(64)),"UPLOAD_DAILY_LIMIT");UploadApprovalDatabaseChecks.assertCode(()->service.issuePermit(account),"UPLOAD_RATE_LIMITED");
        org.assertj.core.api.Assertions.assertThat(db.queryForObject("SELECT approved_bytes FROM upload_approval_daily",Long.class)).isEqualTo(6291456);
        clock.now=clock.now.plus(java.time.Duration.ofDays(1));org.assertj.core.api.Assertions.assertThat(service.approve(account,r2,6291456,"a".repeat(64)).attempt()).isNotNull();
        org.assertj.core.api.Assertions.assertThat(db.queryForObject("SELECT COUNT(*) FROM upload_approval_daily",Integer.class)).isEqualTo(2);
    }
    static org.springframework.jdbc.core.JdbcTemplate database(){
        var db=UploadReservationsTests.database();
        db.execute("ALTER TABLE song ADD representative_recording_id BINARY(16)");
        db.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,current_recording_id BINARY(16),pending_recording_id BINARY(16),operation_id BINARY(16),requested_at TIMESTAMP,PRIMARY KEY(user_id,slot_no))");
        db.execute("CREATE TABLE cloud_hold(id BINARY(16),user_id BINARY(16),recording_id BINARY(16),reason VARCHAR(32))");
        db.execute("CREATE TABLE recording_asset(user_id BINARY(16),recording_id BINARY(16),cloud_state VARCHAR(20),cloud_revision BIGINT,verified_size BIGINT,sha256 VARCHAR(64),generation BINARY(16),object_key VARCHAR(512),stored_at TIMESTAMP,blocked_reason VARCHAR(32),created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        db.execute("CREATE TABLE upload_approval_daily(user_id BINARY(16),utc_day DATE,approved_bytes BIGINT CHECK(approved_bytes BETWEEN 0 AND 104857600),PRIMARY KEY(user_id,utc_day))");
        db.execute("CREATE TABLE upload_url_issue(user_id BINARY(16),id BINARY(16),issued_at TIMESTAMP(3),PRIMARY KEY(user_id,id))");
        db.execute("CREATE TABLE mutation_receipt(user_id BINARY(16),op_id BINARY(16),request_hash VARCHAR(64),response_status INT,response_body VARCHAR(20000),created_at TIMESTAMP(3),expires_at TIMESTAMP(3),PRIMARY KEY(user_id,op_id))");
        return db;
    }
}
