package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.revision.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations.Reply;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.auth.OwnershipTests.bytes;

class MutationFailureTests {
    final IdempotencyTests f=new IdempotencyTests();
    CreationGuard guard;RevisionChanges revisions;UUID id=UUID.randomUUID();
    @BeforeEach void setup() throws Exception {
        f.setup();new ResourceDatabasePopulator(new ClassPathResource("revision-schema.sql")).populate(f.keeper);
        f.jdbc.execute("CREATE TABLE deletion_ledger(user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),object_generation BINARY(16),revision BIGINT)");
        guard=new CreationGuard(f.jdbc,f.access,f.manager);revisions=new RevisionChanges(f.jdbc,f.access,f.manager,f.clock);
    }
    @AfterEach void close() throws Exception { f.close(); }
    Reply create(String op) {
        return f.mutations.execute(f.account,op,"POST","/v1/songs","{\"id\":\""+id+"\"}",()->{
            var result=guard.create(f.account,CreationGuard.Resource.SONG,id,()->{
                f.jdbc.update("INSERT INTO song(id,user_id,revision,title,lifecycle_state) VALUES(?,?,1,'initial','ACTIVE')",bytes(id),bytes(f.registration.userId()));
                return 1;
            });
            return new Reply(result.created()?201:200,"{\"created\":"+result.created()+",\"revision\":"+(result.created()?1:result.existing().revision())+"}");
        });
    }
    void expireReceipts() {
        f.clock.instant=f.clock.instant.plus(Duration.ofDays(91));
        f.jdbc.update("DELETE FROM mutation_receipt WHERE expires_at<=?",LocalDateTime.ofInstant(f.clock.instant,ZoneOffset.UTC));
        var tokens=f.sessions.issue(f.registration);f.account=f.access.authenticate("Bearer "+tokens.accessToken(),f.registration.deviceId().toString());
    }
    @Test void committedResponseLostThenRetryReplaysWithoutAnotherInsert() {
        var discarded=create(f.key); // Transport discards the committed response; the server result is retained only for assertion.
        assertThat(create(f.key)).isEqualTo(discarded);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isEqualTo(1);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);
    }
    @Test void expiredReceiptRetryKeepsExistingUuidAndLaterEdits() {
        create(f.key);f.jdbc.update("UPDATE song SET title='newer',revision=7 WHERE id=?",bytes(id));expireReceipts();
        var result=create(f.key);assertThat(result.status()).isEqualTo(200);assertThat(result.body()).contains("\"created\":false","\"revision\":7");
        assertThat(f.jdbc.queryForObject("SELECT title FROM song",String.class)).isEqualTo("newer");
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isEqualTo(1);
    }
    @Test void expiredReceiptCannotResurrectPurgedUuidEvenWithNewOperationId() {
        create(f.key);f.jdbc.update("INSERT INTO deletion_ledger VALUES(?,'SONG',?,NULL,2)",bytes(f.registration.userId()),bytes(id));
        f.jdbc.update("DELETE FROM song WHERE id=?",bytes(id));expireReceipts();
        for(String op:List.of(f.key,UUID.randomUUID().toString()))
            assertThatThrownBy(()->create(op)).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).isEqualTo("RESOURCE_PURGED");assertThat(e.details()).isEmpty();});
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isZero();
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger",Integer.class)).isEqualTo(1);
    }
    @Test void tombstoneWinsEvenIfLiveRowRemains() {
        create(f.key);f.jdbc.update("INSERT INTO deletion_ledger VALUES(?,'SONG',?,NULL,2)",bytes(f.registration.userId()),bytes(id));expireReceipts();
        assertThatThrownBy(()->create(f.key)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("RESOURCE_PURGED"));
    }
    @Test void trashAndPurgePendingDoNotCallCreationCallback() {
        create(f.key);
        for(String state:List.of("TRASHED","PURGE_PENDING")) {
            f.jdbc.update("UPDATE song SET lifecycle_state=? WHERE id=?",state,bytes(id));
            new org.springframework.transaction.support.TransactionTemplate(f.manager).executeWithoutResult(s->{
                var result=guard.create(f.account,CreationGuard.Resource.SONG,id,()->{throw new AssertionError("Must not recreate");});
                assertThat(result.created()).isFalse();assertThat(result.existing().state()).isEqualTo(state);
            });
        }
    }
    @Test void oldEditAfterReceiptExpiryFailsRevisionCheck() {
        create(f.key);String editKey=UUID.randomUUID().toString();
        java.util.function.Supplier<Reply> edit=()->{var row=revisions.change(f.account,RevisionChanges.Resource.SONG,id.toString(),1L,current->f.jdbc.update("UPDATE song SET title='edited' WHERE id=?",bytes(id)));return new Reply(200,"{\"revision\":"+row.get("revision")+"}");};
        f.mutations.execute(f.account,editKey,"PATCH","/v1/songs/"+id,"{\"base_revision\":1}",edit);expireReceipts();
        assertThatThrownBy(()->f.mutations.execute(f.account,editKey,"PATCH","/v1/songs/"+id,"{\"base_revision\":1}",edit))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REVISION_CONFLICT"));
        assertThat(f.jdbc.queryForObject("SELECT revision FROM song",Long.class)).isEqualTo(2);
    }
    @Test void expiredReceiptConcurrentRetriesStillCreateOnce() throws Exception {
        create(f.key);expireReceipts();
        try(var pool=Executors.newFixedThreadPool(2)) {
            var gate=new CountDownLatch(1);Callable<Reply> work=()->{gate.await();return create(f.key);};
            var a=pool.submit(work);var b=pool.submit(work);gate.countDown();assertThat(a.get(10,TimeUnit.SECONDS)).isEqualTo(b.get(10,TimeUnit.SECONDS));
        }
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isEqualTo(1);
    }
    @Test void failedCreationRollsBackRowAndReceiptThenRetryWorks() {
        assertThatThrownBy(()->f.mutations.execute(f.account,f.key,"POST","/v1/songs","{}",()->guard.<Reply>create(f.account,CreationGuard.Resource.SONG,id,()->{
            f.jdbc.update("INSERT INTO song(id,user_id,revision) VALUES(?,?,1)",bytes(id),bytes(f.registration.userId()));throw new IllegalStateException("injected");
        }).value())).isInstanceOf(IllegalStateException.class);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isZero();assertThat(create(f.key).status()).isEqualTo(201);
    }
    @Test void otherAccountTombstoneDoesNotBlockOwnUuidAndTransactionIsRequired() {
        f.jdbc.update("INSERT INTO deletion_ledger VALUES(?,'SONG',?,NULL,2)",bytes(f.other.principal().userId()),bytes(id));
        assertThat(create(f.key).status()).isEqualTo(201);
        assertThatThrownBy(()->guard.create(f.account,CreationGuard.Resource.SONG,UUID.randomUUID(),()->1)).isInstanceOf(IllegalStateException.class);
    }
    @Test void differentOperationsRacingForNewUuidCreateOnlyOnce() throws Exception {
        try(var pool=Executors.newFixedThreadPool(2)) {
            var gate=new CountDownLatch(1);
            var a=pool.submit(()->{gate.await();return create(f.key);});
            var b=pool.submit(()->{gate.await();return create(UUID.randomUUID().toString());});
            gate.countDown();assertThat(List.of(a.get(10,TimeUnit.SECONDS).status(),b.get(10,TimeUnit.SECONDS).status())).containsExactlyInAnyOrder(201,200);
        }
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song",Integer.class)).isEqualTo(1);
    }

}
