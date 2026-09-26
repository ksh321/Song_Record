package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.sync.AccountChanges.*;
import com.ksh321.songrecord.api.revision.RevisionChanges.Resource;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations.Reply;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

class AccountChangesTests {
    final RevisionTests f=new RevisionTests();AccountChanges changes;
    @BeforeEach void setup() throws Exception {
        f.setup();new ResourceDatabasePopulator(new ClassPathResource("change-log-schema.sql")).populate(f.f.keeper);
        changes=new AccountChanges(f.f.jdbc,f.f.access,f.f.manager,f.f.clock);
    }
    @AfterEach void close() throws Exception {f.close();}
    Change event(long revision){return new Change(Entity.PLAYLIST,f.id,revision,Operation.UPSERT,"{\"name\":\"edited\"}");}
    Reply rename(String key,long base) {
        return f.f.mutations.execute(f.f.account,key,"PATCH","/v1/playlists/"+f.id,"{\"base_revision\":"+base+"}",()->{
            var result=changes.write(f.f.account,()->{
                var current=f.changes.change(f.f.account,Resource.PLAYLIST,f.id.toString(),base,before->f.f.jdbc.update("UPDATE playlist SET name='edited' WHERE id=?",OwnershipTests.bytes(f.id)));
                return new Batch<>(current,List.of(new Change(Entity.PLAYLIST,f.id,((Number)current.get("revision")).longValue(),Operation.UPSERT,f.json.writeValueAsString(current))));
            });
            return new Reply(200,f.json.writeValueAsString(Map.of("current",result.value(),"change_seq",result.lastChangeSeq())));
        });
    }
    long seq(){return f.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,OwnershipTests.bytes(f.f.registration.userId()));}
    int logs(){return f.f.jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class);}
    @Test void businessRevisionReceiptAndSequenceCommitTogetherAndReplayDoesNotAppend() {
        var key=UUID.randomUUID().toString();var first=rename(key,1);
        assertThat(rename(key,1)).isEqualTo(first);assertThat(seq()).isEqualTo(1);assertThat(logs()).isEqualTo(1);
        assertThat(f.f.jdbc.queryForObject("SELECT revision FROM playlist",Long.class)).isEqualTo(2);
        assertThat(f.f.jdbc.queryForObject("SELECT revision FROM change_log",Long.class)).isEqualTo(2);
        rename(UUID.randomUUID().toString(),2);assertThat(seq()).isEqualTo(2);
    }
    @Test void revisionConflictDoesNotConsumeSequenceOrReceipt() {
        rename(UUID.randomUUID().toString(),1);
        assertThatThrownBy(()->rename(UUID.randomUUID().toString(),1)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REVISION_CONFLICT"));
        assertThat(seq()).isEqualTo(1);assertThat(logs()).isEqualTo(1);
    }
    @Test void logFailureRollsBackBusinessRevisionReceiptAndCounter() {
        f.f.jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT injected CHECK(revision=1)");
        assertThatThrownBy(()->rename(UUID.randomUUID().toString(),1)).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertThat(seq()).isZero();assertThat(logs()).isZero();
        assertThat(f.f.jdbc.queryForObject("SELECT name FROM playlist",String.class)).isEqualTo("before");
        assertThat(f.f.jdbc.queryForObject("SELECT revision FROM playlist",Long.class)).isEqualTo(1);
        assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
    }
    @Test void outerRollbackAfterLogLeavesNothingCommitted() {
        assertThatThrownBy(()->new TransactionTemplate(f.f.manager).execute(s->{
            changes.write(f.f.account,()->{f.f.jdbc.update("UPDATE playlist SET name='bad'");return new Batch<>("ok",List.of(event(1)));});
            throw new IllegalStateException();
        })).isInstanceOf(IllegalStateException.class);
        assertThat(seq()).isZero();assertThat(logs()).isZero();
        assertThat(f.f.jdbc.queryForObject("SELECT name FROM playlist",String.class)).isEqualTo("before");
    }
    @Test void multipleEventsGetContiguousSequencesAndNinetyDayExpiry() {
        var result=new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->new Batch<>("ok",List.of(event(2),new Change(Entity.TAG,UUID.randomUUID(),3,Operation.DELETE,"{}")))));
        assertThat(result.lastChangeSeq()).isEqualTo(2);assertThat(result.value()).isEqualTo("ok");
        assertThat(f.f.jdbc.queryForList("SELECT change_seq FROM change_log ORDER BY change_seq",Long.class)).containsExactly(1L,2L);
        var created=f.f.jdbc.queryForObject("SELECT created_at FROM change_log WHERE change_seq=1",java.time.LocalDateTime.class);
        assertThat(f.f.jdbc.queryForObject("SELECT expires_at FROM change_log WHERE change_seq=1",java.time.LocalDateTime.class)).isEqualTo(created.plusDays(90));
    }
    @Test void accountsHaveIndependentSequenceSpaces() {
        new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->new Batch<>(1,List.of(event(1)))));
        var other=new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.other,()->new Batch<>(1,List.of(new Change(Entity.TAG,UUID.randomUUID(),1,Operation.UPSERT,"{}")))));
        assertThat(other.lastChangeSeq()).isEqualTo(1);assertThat(seq()).isEqualTo(1);assertThat(logs()).isEqualTo(2);
    }
    @Test void invalidPayloadAndEmptyChangesCannotCommit() {
        assertThatThrownBy(()->new Change(Entity.TAG,UUID.randomUUID(),1,Operation.UPSERT,"[]")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(()->new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->{f.f.jdbc.update("UPDATE playlist SET name='bad'");return new Batch<>(1,List.of());}))).isInstanceOf(IllegalArgumentException.class);
        assertThat(f.f.jdbc.queryForObject("SELECT name FROM playlist",String.class)).isEqualTo("before");assertThat(seq()).isZero();
    }
    @Test void requiresTransactionAndLiveSession() {
        assertThatThrownBy(()->changes.write(f.f.account,()->new Batch<>(1,List.of(event(1))))).isInstanceOf(IllegalStateException.class);
        f.f.sessions.logout(f.f.tokens.refreshToken(),f.f.registration.deviceId());
        assertThatThrownBy(()->new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->{throw new AssertionError();}))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(401));
    }
    @Test void overflowRollsBackCallbackEdits() {
        f.f.jdbc.update("UPDATE user_sync_state SET last_change_seq=? WHERE user_id=?",Long.MAX_VALUE,OwnershipTests.bytes(f.f.registration.userId()));
        assertThatThrownBy(()->new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->{f.f.jdbc.update("UPDATE playlist SET name='bad'");return new Batch<>(1,List.of(event(1)));}))).isInstanceOf(IllegalStateException.class);
        assertThat(f.f.jdbc.queryForObject("SELECT name FROM playlist",String.class)).isEqualTo("before");assertThat(logs()).isZero();
    }
    @Test void accountLockPreventsLaterCommitFromAppearingBehindCursor() throws Exception {
        var firstInside=new CountDownLatch(1);var releaseFirst=new CountDownLatch(1);
        var secondInside=new CountDownLatch(1);var releaseSecond=new CountDownLatch(1);var secondStarted=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var first=pool.submit(()->new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->{firstInside.countDown();await(releaseFirst);return new Batch<>(1,List.of(event(1)));})));
            assertThat(firstInside.await(5,TimeUnit.SECONDS)).isTrue();
            var second=pool.submit(()->{secondStarted.countDown();return new TransactionTemplate(f.f.manager).execute(s->changes.write(f.f.account,()->{secondInside.countDown();await(releaseSecond);return new Batch<>(2,List.of(event(2)));}));});
            try {
                assertThat(secondStarted.await(5,TimeUnit.SECONDS)).isTrue();assertThat(secondInside.await(200,TimeUnit.MILLISECONDS)).isFalse();
                assertThat(seq()).isZero();assertThat(logs()).isZero();
                releaseFirst.countDown();assertThat(first.get(5,TimeUnit.SECONDS).lastChangeSeq()).isEqualTo(1);
                assertThat(secondInside.await(5,TimeUnit.SECONDS)).isTrue();assertThat(seq()).isEqualTo(1);assertThat(logs()).isEqualTo(1);
                releaseSecond.countDown();assertThat(second.get(5,TimeUnit.SECONDS).lastChangeSeq()).isEqualTo(2);
                assertThat(f.f.jdbc.queryForList("SELECT change_seq FROM change_log WHERE change_seq>1",Long.class)).containsExactly(2L);
            } finally {releaseFirst.countDown();releaseSecond.countDown();}
        }
    }
    static void await(CountDownLatch latch){try{if(!latch.await(8,TimeUnit.SECONDS))throw new IllegalStateException("Test gate timeout");}catch(InterruptedException e){Thread.currentThread().interrupt();throw new IllegalStateException(e);}}
}
