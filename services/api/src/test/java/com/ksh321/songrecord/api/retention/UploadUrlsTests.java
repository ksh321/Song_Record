package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.uploads.*;
import com.ksh321.songrecord.api.idempotency.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static com.ksh321.songrecord.api.retention.UploadApprovalDatabaseChecks.assertCode;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
class UploadUrlsTests {
    @Test void issuanceReplayRenewalExpiryIsolationAndRollback(){
        var db=UploadApprovalTests.database();var manager=new DataSourceTransactionManager(db.getDataSource());
        UUID owner=account(db),device=device(db,owner),recording=recording(db,owner,device,null,true,true,"VALIDATED");
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(owner));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(owner));
        db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id) VALUES(?,1,?)",bytes(owner),bytes(recording));
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture",device.toString())).thenReturn(account);when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,device,UUID.randomUUID()));
        var clock=new UploadApprovalDatabaseChecks.MutableClock();var mutations=new IdempotentMutations(db,access,manager,clock);
        var approval=new UploadApproval(db,access,manager,clock,mutations);var calls=new java.util.concurrent.atomic.AtomicInteger();
        UploadPutSigner signer=(key,expiry)->{calls.incrementAndGet();return new UploadPutSigner.SignedPut("https://fixture.invalid/"+key.value(),clock.instant().plusSeconds(Math.min(600,Duration.between(clock.instant(),expiry).getSeconds())),Map.of());};
        var urls=new UploadUrls(db,access,manager,mutations,approval,signer,clock);
        String body="{\"expected_size\":6291456,\"sha256\":\""+"a".repeat(64)+"\"}",op=UUID.randomUUID().toString();
        var reply=urls.authorize("fixture",device.toString(),op,recording,body);
        var json=new tools.jackson.databind.json.JsonMapper().readTree(reply.body());UUID attempt=UUID.fromString(json.get("attempt_id").asText());
        Instant original=Instant.parse(json.get("attempt_expires_at").asText());
        assertThat(original).isEqualTo(clock.instant().plus(Duration.ofHours(24)));
        assertThat(json.get("state").asText()).isEqualTo("UPLOADING");
        assertThat(urls.authorize("fixture",device.toString(),op,recording,body)).isEqualTo(reply);assertThat(calls.get()).isEqualTo(1);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM upload_url_issue",Long.class)).isEqualTo(1);
        clock.now=clock.now.plusSeconds(60);op=UUID.randomUUID().toString();var renewed=urls.renew("fixture",device.toString(),op,attempt);
        assertThat(urls.renew("fixture",device.toString(),op,attempt)).isEqualTo(renewed);assertThat(calls.get()).isEqualTo(2);
        assertThat(db.queryForObject("SELECT expires_at FROM recording_upload",java.sql.Timestamp.class).toInstant()).isEqualTo(original);
        // A signer failure must roll back its permit, state and idempotency receipt.
        var broken=new UploadUrls(db,access,manager,mutations,approval,(k,e)->{throw new IllegalStateException("sign failed");},clock);
        long permits=db.queryForObject("SELECT COUNT(*) FROM upload_url_issue",Long.class),receipts=db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Long.class);
        assertThatThrownBy(()->broken.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt)).isInstanceOf(IllegalStateException.class);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM upload_url_issue",Long.class)).isEqualTo(permits);assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Long.class)).isEqualTo(receipts);
        UUID second=recording(db,owner,device,null,true,true,"VALIDATED");
        db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id) VALUES(?,2,?)",bytes(owner),bytes(second));
        assertThatThrownBy(()->broken.authorize("fixture",device.toString(),UUID.randomUUID().toString(),second,body)).isInstanceOf(IllegalStateException.class);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_upload",Long.class)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT approved_bytes FROM upload_approval_daily",Long.class)).isEqualTo(6291456);
        UUID other=account(db),otherDevice=device(db,other);var otherAccount=mock(AccountAccess.Account.class);
        db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(other));db.update("INSERT INTO user_entitlement(user_id) VALUES(?)",bytes(other));db.update("INSERT INTO storage_usage(user_id) VALUES(?)",bytes(other));
        when(access.authenticate("other",otherDevice.toString())).thenReturn(otherAccount);when(access.revalidate(otherAccount)).thenReturn(new SessionService.Principal(other,otherDevice,UUID.randomUUID()));
        assertCode(()->urls.renew("other",otherDevice.toString(),UUID.randomUUID().toString(),attempt),"RESOURCE_NOT_FOUND");
        assertCode(()->urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),UUID.randomUUID()),"RESOURCE_NOT_FOUND");
        db.update("UPDATE recording_upload SET state='VERIFYING'");assertCode(()->urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt),"UPLOAD_STATE_CONFLICT");db.update("UPDATE recording_upload SET state='UPLOADING'");
        db.update("DELETE FROM pin_slot WHERE user_id=?",bytes(owner));
        assertCode(()->urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt),"NOT_CLOUD_TARGET");
        db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id) VALUES(?,1,?)",bytes(owner),bytes(recording));
        // Distinct operations cannot evade the shared 10 URL/minute budget.
        for(int i=0;i<9;i++)urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt);
        assertCode(()->urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt),"UPLOAD_RATE_LIMITED");
        clock.now=original.minusSeconds(20);var last=new tools.jackson.databind.json.JsonMapper().readTree(urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt).body());
        assertThat(Instant.parse(last.get("expires_at").asText())).isEqualTo(original);
        clock.now=original;assertCode(()->urls.renew("fixture",device.toString(),UUID.randomUUID().toString(),attempt),"UPLOAD_EXPIRED");
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(6291456);
    }
}
