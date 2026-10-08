package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.uploads.*;
import com.ksh321.songrecord.api.jobs.*;
import com.ksh321.songrecord.api.idempotency.*;
import java.time.*;
import java.util.*;
import java.io.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;
import static com.ksh321.songrecord.api.retention.UploadApprovalDatabaseChecks.assertCode;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

public final class UploadCompletionDatabaseChecks {
    public static void verify(JdbcTemplate db)throws Exception {
        var manager=new DataSourceTransactionManager(db.getDataSource());
        UUID owner=account(db),dev=device(db,owner),recording=recording(db,owner,dev,null,false,false,"VALIDATED");
        db.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,3,1000,'AAC_LC',48000,1,'VALIDATED')",bytes(recording),bytes(owner),"a".repeat(64));
        db.update("UPDATE recording SET metadata_state='SAVED' WHERE id=?",bytes(recording));
        for(String table:List.of("user_sync_state","user_entitlement","storage_usage"))db.update("INSERT INTO "+table+"(user_id) VALUES(?)",bytes(owner));
        db.update("INSERT INTO pin_slot(user_id,slot_no,pending_recording_id) VALUES(?,1,?)",bytes(owner),bytes(recording));
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);
        when(access.authenticate("fixture",dev.toString())).thenReturn(account);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,dev,UUID.randomUUID()));
        var clock=new UploadApprovalDatabaseChecks.MutableClock();
        var mutations=new IdempotentMutations(db,access,manager,clock);
        var jobs=new JobQueue(db,access,manager,clock,Duration.ofMinutes(2),5);
        var reservations=new UploadReservations(db,access,manager,clock);
        var reservation=reservations.reserve(account,new UploadReservations.Request(recording,3,"a".repeat(64),1));UUID attempt=reservation.attempt();
        var completion=new UploadCompletion(db,access,manager,mutations,jobs,clock);
        assertCode(()->completion.complete("fixture",dev.toString(),UUID.randomUUID().toString(),attempt),"UPLOAD_STATE_CONFLICT");
        var approval=new UploadApproval(db,access,manager,clock,mutations);
        var urls=new UploadUrls(db,access,manager,mutations,approval,(key,expiry)->new UploadPutSigner.SignedPut("https://fixture.invalid/put",clock.instant().plusSeconds(600),Map.of()),clock);
        assertThat(urls.renew("fixture",dev.toString(),UUID.randomUUID().toString(),attempt).status()).isEqualTo(200);
        var brokenJobs=mock(JobQueue.class);when(brokenJobs.enqueue(any(),any(),any(),any(),anyString())).thenAnswer(call->{jobs.enqueue(account,JobQueue.Type.UPLOAD_VERIFY,attempt,attempt,"{}");throw new IllegalStateException("fixture");});
        var broken=new UploadCompletion(db,access,manager,mutations,brokenJobs,clock);
        int before=db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class);
        assertThatThrownBy(()->broken.complete("fixture",dev.toString(),UUID.randomUUID().toString(),attempt)).isInstanceOf(IllegalStateException.class);
        assertThat(db.queryForObject("SELECT state FROM recording_upload WHERE id=?",String.class,bytes(attempt))).isEqualTo("UPLOADING");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(before);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE aggregate_id=?",Integer.class,bytes(attempt))).isZero();
        String op=UUID.randomUUID().toString();var first=completion.complete("fixture",dev.toString(),op,attempt);
        assertThat(first.status()).isEqualTo(202);
        assertThat(completion.complete("fixture",dev.toString(),op,attempt)).isEqualTo(first);
        assertThat(completion.complete("fixture",dev.toString(),UUID.randomUUID().toString(),attempt)).isEqualTo(first);
        assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE aggregate_id=?",Integer.class,bytes(attempt))).isEqualTo(1);
        assertThat(db.queryForObject("SELECT state FROM recording_upload WHERE id=?",String.class,bytes(attempt))).isEqualTo("VERIFYING");
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(3);
        UUID other=account(db),od=device(db,other);for(String table:List.of("user_sync_state","user_entitlement","storage_usage"))db.update("INSERT INTO "+table+"(user_id) VALUES(?)",bytes(other));
        var otherAccount=mock(AccountAccess.Account.class);when(access.authenticate("other",od.toString())).thenReturn(otherAccount);when(access.revalidate(otherAccount)).thenReturn(new SessionService.Principal(other,od,UUID.randomUUID()));
        assertCode(()->completion.complete("other",od.toString(),UUID.randomUUID().toString(),attempt),"RESOURCE_NOT_FOUND");
        // A new HTTP operation still converges on the same durable job under concurrent requests.
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            var gate=new java.util.concurrent.CountDownLatch(1);
            java.util.concurrent.Callable<IdempotentMutations.Reply> call=()->{gate.await();return completion.complete("fixture",dev.toString(),UUID.randomUUID().toString(),attempt);};
            var a=pool.submit(call);var b=pool.submit(call);gate.countDown();assertThat(a.get(10,java.util.concurrent.TimeUnit.SECONDS)).isEqualTo(first);assertThat(b.get(10,java.util.concurrent.TimeUnit.SECONDS)).isEqualTo(first);
        }
        var lease=jobs.claim(JobQueue.Type.UPLOAD_VERIFY).orElseThrow();
        var reads=new java.util.concurrent.atomic.AtomicInteger();var closed=new java.util.concurrent.atomic.AtomicBoolean();
        UploadByteSource source=key->{reads.incrementAndGet();assertThat(key.attempt()).isEqualTo(attempt);return new ByteArrayInputStream(new byte[]{1,2,3}){@Override public void close()throws IOException{closed.set(true);super.close();}};};
        var verification=new UploadVerification(db,source,clock);
        var effects=verification.prepare(lease,(l,captured)->{
            assertThat(org.springframework.transaction.support.TransactionSynchronizationManager.isActualTransactionActive()).isFalse();
            assertThat(captured.bytes().isReadOnly()).isTrue();var data=new byte[3];captured.bytes().get(data);assertThat(data).containsExactly(1,2,3);
            assertThat(captured.expectedSize()).isEqualTo(3);assertThat(captured.toString()).isEqualTo("CapturedUpload[REDACTED]");return ()->{};
        });
        assertThat(reads.get()).isEqualTo(1);assertThat(closed.get()).isTrue();
        // Byte acquisition alone never completes the job, asset, reservation or upload.
        assertThat(db.queryForObject("SELECT state FROM job WHERE id=?",String.class,bytes(lease.id()))).isEqualTo("RUNNING");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_asset WHERE user_id=? AND cloud_state='STORED'",Integer.class,bytes(owner))).isZero();
        db.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));
        assertThatThrownBy(()->verification.prepare(lease,(l,c)->()->{})).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(effects::run).isInstanceOf(IllegalStateException.class);assertThat(reads.get()).isEqualTo(1);
        db.update("UPDATE app_user SET status='ACTIVE' WHERE id=?",bytes(owner));
        var oversize=new UploadVerification(db,key->new ByteArrayInputStream(new byte[UploadVerification.MAX_BYTES+1]),clock);
        assertThatThrownBy(()->oversize.prepare(lease,(l,c)->{throw new AssertionError("oversize reached validator");})).isInstanceOf(IOException.class);
        var missing=new UploadVerification(db,key->{throw new IllegalStateException("UPLOAD_BYTES_UNAVAILABLE");},clock);
        assertThatThrownBy(()->missing.prepare(lease,(l,c)->()->{})).isInstanceOf(IllegalStateException.class);
        clock.now=clock.now.plusSeconds(121);
        assertThatThrownBy(()->verification.prepare(lease,(l,c)->()->{})).isInstanceOf(IllegalStateException.class);
        assertThat(reads.get()).isEqualTo(1);
        clock.now=reservation.expiresAt();assertCode(()->completion.complete("fixture",dev.toString(),UUID.randomUUID().toString(),attempt),"UPLOAD_EXPIRED");
        assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(3);
    }
}
