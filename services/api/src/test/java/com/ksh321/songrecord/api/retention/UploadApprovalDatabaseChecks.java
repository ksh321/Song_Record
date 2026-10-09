package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.uploads.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

public final class UploadApprovalDatabaseChecks {
    public static void verify(JdbcTemplate db)throws Exception {
        UUID owner=account(db),dev=device(db,owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(owner));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(owner));
        var access=mock(AccountAccess.class);var a=mock(AccountAccess.Account.class);when(access.revalidate(a)).thenReturn(new SessionService.Principal(owner,dev,UUID.randomUUID()));
        var manager=new DataSourceTransactionManager(db.getDataSource());var clock=new MutableClock();var approvals=new UploadApproval(db,access,manager,clock,new com.ksh321.songrecord.api.idempotency.IdempotentMutations(db,access,manager,clock));
        UUID r1=recording(db,owner,dev,null,true,true,"VALIDATED"),r2=recording(db,owner,dev,null,true,true,"VALIDATED"),r3=recording(db,owner,dev,null,true,true,"VALIDATED");
        for(int i=0;i<3;i++)db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id,operation_id,requested_at) VALUES(?,?,?,?,CURRENT_TIMESTAMP)",bytes(owner),i+1,bytes(List.of(r1,r2,r3).get(i)),bytes(UUID.randomUUID()));
        assertCode(()->approvals.approve(a,r1,1,"a".repeat(64)),"FILE_SPEC_MISMATCH");
        db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(r1));
        assertCode(()->approvals.approve(a,r1,6291456,"a".repeat(64)),"NOT_CLOUD_TARGET");
        db.update("UPDATE recording SET lifecycle_state='ACTIVE',deleted_at=NULL WHERE id=?",bytes(r1));
        var first=approvals.approve(a,r1,6291456,"a".repeat(64));
        when(access.authenticate("Bearer fixture",dev.toString())).thenReturn(a);
        String op=UUID.randomUUID().toString(),body=new tools.jackson.databind.json.JsonMapper().writeValueAsString(Map.of("expected_size",6291456,"sha256","a".repeat(64)));
        var reply=approvals.authorize("Bearer fixture",dev.toString(),op,r1,body);
        assertThat(approvals.authorize("Bearer fixture",dev.toString(),op,r1,body)).isEqualTo(reply);
        assertCode(()->approvals.authorize("Bearer fixture",dev.toString(),op,r1,body.replace("6291456","1")),"IDEMPOTENCY_CONFLICT");
        assertThat(approvals.approve(a,r1,6291456,"a".repeat(64))).isEqualTo(first);
        // Remaining one slot: only one simultaneous approval can win.
        var race=UploadReservationDatabaseChecks.race(()->approvals.approve(a,r2,6291456,"a".repeat(64)),()->approvals.approve(a,r3,6291456,"a".repeat(64)));
        assertThat(race.stream().filter(UploadApproval.Approval.class::isInstance).count()).isEqualTo(1);assertThat(race).contains("UPLOAD_CONCURRENCY_LIMIT");
        assertThat(db.queryForObject("SELECT approved_bytes FROM upload_approval_daily WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(12582912);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM upload_url_issue WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(2);
        for(int i=0;i<8;i++)approvals.issuePermit(a);
        assertCode(()->approvals.issuePermit(a),"UPLOAD_RATE_LIMITED");
        clock.now=clock.now.plusSeconds(59);assertCode(()->approvals.issuePermit(a),"UPLOAD_RATE_LIMITED");
        clock.now=clock.now.plusSeconds(1);approvals.issuePermit(a);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM upload_url_issue WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(1);
        // A second account's daily quota is independent; exact UTC boundary resets only daily allowance.
        UUID other=account(db),od=device(db,other),song=song(db,other),r=recording(db,other,od,song,true,true,"VALIDATED");
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(other));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(other));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(other));
        var b=mock(AccountAccess.Account.class);when(access.revalidate(b)).thenReturn(new SessionService.Principal(other,od,UUID.randomUUID()));
        // No persisted selection: fresh latest-role calculation must authorize the current recording.
        var day=java.sql.Date.valueOf(LocalDate.ofInstant(clock.now,ZoneOffset.UTC));db.update("INSERT INTO upload_approval_daily(user_id,utc_day,approved_bytes) VALUES(?,?,104857600)",bytes(other),day);
        assertCode(()->approvals.approve(b,r,6291456,"a".repeat(64)),"UPLOAD_DAILY_LIMIT");
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(other))).isZero();
        db.update("UPDATE upload_approval_daily SET approved_bytes=104857600-6291456 WHERE user_id=?",bytes(other));
        assertThat(approvals.approve(b,r,6291456,"a".repeat(64))).isNotNull();
        assertThat(db.queryForObject("SELECT approved_bytes FROM upload_approval_daily WHERE user_id=?",Long.class,bytes(other))).isEqualTo(104857600);
        clock.now=Instant.parse("2026-10-09T00:00:00Z");UUID next=recording(db,other,od,song,true,true,"VALIDATED");
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",bytes(next),bytes(song));
        assertThat(approvals.approve(b,next,6291456,"a".repeat(64))).isNotNull();
        assertThat(db.queryForObject("SELECT approved_bytes FROM upload_approval_daily WHERE user_id=? AND utc_day='2026-10-09'",Long.class,bytes(other))).isEqualTo(6291456);
        assertCode(()->approvals.approve(a,r,6291456,"a".repeat(64)),"RESOURCE_NOT_FOUND");
        UUID stored=recording(db,other,od,null,true,true,"VALIDATED");
        db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,cloud_revision,verified_size,sha256,generation,object_key,stored_at) VALUES(?,?,'STORED',1,6291456,?,?,'fixture/stored',CURRENT_TIMESTAMP)",bytes(stored),bytes(other),"a".repeat(64),1L);
        db.update("INSERT INTO pin_slot(user_id,slot_no,current_recording_id,operation_id,requested_at) VALUES(?,1,?,?,CURRENT_TIMESTAMP)",bytes(other),bytes(stored),bytes(UUID.randomUUID()));
        long before=db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(other));
        assertThat(approvals.approve(b,stored,6291456,"a".repeat(64)).state()).isEqualTo("STORED");
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(other))).isEqualTo(before);
        UUID unselected=recording(db,other,od,null,true,true,"VALIDATED");assertCode(()->approvals.approve(b,unselected,6291456,"a".repeat(64)),"NOT_CLOUD_TARGET");
        UUID third=account(db),td=device(db,third);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(third));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(third));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(third));
        var c=mock(AccountAccess.Account.class);when(access.revalidate(c)).thenReturn(new SessionService.Principal(third,td,UUID.randomUUID()));
        UUID ca=recording(db,third,td,null,true,true,"VALIDATED"),cb=recording(db,third,td,null,true,true,"VALIDATED");
        int slot=0;for(UUID id:List.of(ca,cb))db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id,operation_id,requested_at) VALUES(?,?,?,?,CURRENT_TIMESTAMP)",bytes(third),++slot,bytes(id),bytes(UUID.randomUUID()));
        for(int i=0;i<10;i++)approvals.issuePermit(c);
        assertCode(()->approvals.approve(c,ca,6291456,"a".repeat(64)),"UPLOAD_RATE_LIMITED");
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(third))).isZero();
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_upload WHERE user_id=?",Long.class,bytes(third))).isZero();
        clock.now=clock.now.plusSeconds(60);
        db.update("INSERT INTO upload_approval_daily(user_id,utc_day,approved_bytes) VALUES(?,'2026-10-09',104857600-6291456)",bytes(third));
        race=UploadReservationDatabaseChecks.race(()->approvals.approve(c,ca,6291456,"a".repeat(64)),()->approvals.approve(c,cb,6291456,"a".repeat(64)));
        assertThat(race.stream().filter(UploadApproval.Approval.class::isInstance).count()).isEqualTo(1);assertThat(race).contains("UPLOAD_DAILY_LIMIT");
        assertThat(db.queryForObject("SELECT approved_bytes FROM upload_approval_daily WHERE user_id=?",Long.class,bytes(third))).isEqualTo(104857600);
    }
    static void assertCode(Runnable call,String code){assertThatThrownBy(call::run).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo(code));}
    static final class MutableClock extends Clock {Instant now=Instant.parse("2026-10-08T12:00:00Z");public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId z){return this;}public Instant instant(){return now;}}
}
