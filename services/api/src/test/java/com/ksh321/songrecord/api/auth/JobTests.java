package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.jobs.*;
import com.ksh321.songrecord.api.jobs.JobQueue.Type;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

class JobTests {
    final IdempotencyTests f=new IdempotencyTests();JobQueue queue;
    UUID aggregate=UUID.randomUUID(),operation=UUID.randomUUID();
    @BeforeEach void setup() throws Exception {
        f.setup();new ResourceDatabasePopulator(new ClassPathResource("job-schema.sql")).populate(f.keeper);
        queue=new JobQueue(f.jdbc,f.access,f.manager,f.clock,Duration.ofSeconds(10),3);
    }
    @AfterEach void close() throws Exception {f.close();}
    UUID enqueue(){return new TransactionTemplate(f.manager).execute(s->queue.enqueue(f.account,Type.UPLOAD_VERIFY,aggregate,operation,"{\"a\":1}"));}
    String state(){return f.jdbc.queryForObject("SELECT state FROM job",String.class);}
    @Test void dedupeReusesSameJobAndRejectsDifferentPayload() {
        assertThat(enqueue()).isEqualTo(enqueue());
        assertThatThrownBy(()->new TransactionTemplate(f.manager).execute(s->queue.enqueue(f.account,Type.UPLOAD_VERIFY,aggregate,operation,"{\"a\":2}"))).isInstanceOf(IllegalArgumentException.class);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(1);
    }
    @Test void accountScopesAreIndependent() {
        enqueue();new TransactionTemplate(f.manager).execute(s->queue.enqueue(f.other,Type.UPLOAD_VERIFY,aggregate,operation,"{}"));
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(2);
    }
    @Test void domainAndJobRollbackTogether() {
        assertThatThrownBy(()->new TransactionTemplate(f.manager).execute(s->{f.effect();queue.enqueue(f.account,Type.UPLOAD_VERIFY,aggregate,operation,"{}");throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
        assertThat(f.count()).isZero();assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isZero();
    }
    @Test void duplicateCompletionDoesNotRepeatBusinessEffect() {
        enqueue();var lease=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();
        assertThat(queue.complete(lease,()->f.effect())).isTrue();assertThat(queue.complete(lease,()->f.effect())).isFalse();
        assertThat(f.count()).isEqualTo(1);assertThat(state()).isEqualTo("SUCCEEDED");assertThat(queue.claim(Type.UPLOAD_VERIFY)).isEmpty();
    }
    @Test void crashedWorkerIsReclaimedAndOldOwnerCannotFinalizeOrRenew() {
        enqueue();var old=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();f.clock.instant=f.clock.instant.plusSeconds(10);
        var next=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();assertThat(next.token()).isNotEqualTo(old.token());
        assertThat(queue.complete(old,()->f.effect())).isFalse();assertThat(queue.fail(old,true)).isFalse();assertThat(queue.renew(old)).isFalse();
        assertThat(queue.complete(next,()->f.effect())).isTrue();assertThat(f.count()).isEqualTo(1);
    }
    @Test void heartbeatExtendsOwnershipAndCannotResurrectExpiredLease() {
        enqueue();var lease=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();f.clock.instant=f.clock.instant.plusSeconds(9);
        assertThat(queue.renew(lease)).isTrue();f.clock.instant=f.clock.instant.plusSeconds(2);assertThat(queue.claim(Type.UPLOAD_VERIFY)).isEmpty();
        f.clock.instant=f.clock.instant.plusSeconds(8);assertThat(queue.renew(lease)).isFalse();
    }
    @Test void retryBackoffAndAttemptLimit() {
        enqueue();var a=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();queue.fail(a,true);assertThat(state()).isEqualTo("RETRY_WAIT");assertThat(queue.claim(Type.UPLOAD_VERIFY)).isEmpty();
        f.clock.instant=f.clock.instant.plusSeconds(5);var b=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();queue.fail(b,true);
        f.clock.instant=f.clock.instant.plusSeconds(10);var c=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();queue.fail(c,true);
        assertThat(state()).isEqualTo("FAILED");assertThat(queue.claim(Type.UPLOAD_VERIFY)).isEmpty();
    }
    @Test void repeatedCrashesEventuallyFail() {
        enqueue();for(int i=0;i<3;i++){assertThat(queue.claim(Type.UPLOAD_VERIFY)).isPresent();f.clock.instant=f.clock.instant.plusSeconds(10);}
        assertThat(queue.claim(Type.UPLOAD_VERIFY)).isEmpty();assertThat(state()).isEqualTo("FAILED");
    }
    @Test void completionExceptionRollsBackEffects() {
        enqueue();var lease=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();
        assertThatThrownBy(()->queue.complete(lease,()->{f.effect();throw new IllegalStateException();})).isInstanceOf(IllegalStateException.class);
        assertThat(f.count()).isZero();assertThat(state()).isEqualTo("RUNNING");
    }
    @Test void expirationDuringCompletionRollsBackEffects() {
        enqueue();var lease=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();
        assertThatThrownBy(()->queue.complete(lease,()->{f.effect();f.clock.instant=f.clock.instant.plusSeconds(10);})).isInstanceOf(IllegalStateException.class);assertThat(f.count()).isZero();
    }
    @Test void runnerPreparationIsOutsideTransactionAndErrorsAreRedacted() {
        enqueue();var runner=new JobRunner(queue);
        assertThat(runner.runOnce(Type.UPLOAD_VERIFY,l->{assertThat(org.springframework.transaction.support.TransactionSynchronizationManager.isActualTransactionActive()).isFalse();throw new IllegalStateException("secret-url-token");})).isTrue();
        assertThat(f.jdbc.queryForObject("SELECT last_error FROM job",String.class)).isEqualTo("EXECUTION_FAILED");
        f.clock.instant=f.clock.instant.plusSeconds(5);runner.runOnce(Type.UPLOAD_VERIFY,l->()->f.effect());assertThat(f.count()).isEqualTo(1);
    }
    @Test void transactionBoundariesAndPayloadValidation() {
        assertThatThrownBy(()->queue.enqueue(f.account,Type.UPLOAD_VERIFY,aggregate,operation,"{}")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(()->new TransactionTemplate(f.manager).execute(s->queue.claim(Type.UPLOAD_VERIFY))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(()->new TransactionTemplate(f.manager).execute(s->queue.enqueue(f.account,Type.UPLOAD_VERIFY,aggregate,operation,"[]"))).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void twoWorkersDoNotClaimSameLiveJob() throws Exception {
        enqueue();try(var pool=Executors.newFixedThreadPool(2)) {
            var gate=new CountDownLatch(1);Callable<Boolean> action=()->{gate.await();return queue.claim(Type.UPLOAD_VERIFY).isPresent();};
            var a=pool.submit(action);var b=pool.submit(action);gate.countDown();assertThat(a.get(10,TimeUnit.SECONDS)).isNotEqualTo(b.get(10,TimeUnit.SECONDS));
        }
    }

    @Test void lostLeaseDuringDomainEffectsRollsBackBeforeNewOwnerCompletes() throws Exception {
        enqueue();var old=queue.claim(Type.UPLOAD_VERIFY).orElseThrow();
        var inside=new CountDownLatch(1);var release=new CountDownLatch(1);
        try(var pool=Executors.newSingleThreadExecutor()) {
            var oldCompletion=pool.submit(()->queue.complete(old,()->{
                com.ksh321.songrecord.api.locking.LockOrder.before(com.ksh321.songrecord.api.locking.LockOrder.Rank.AGGREGATE,"effect");
                f.effect();inside.countDown();try{if(!release.await(8,TimeUnit.SECONDS))throw new IllegalStateException();}catch(InterruptedException e){throw new IllegalStateException(e);}
            }));
            try {
                assertThat(inside.await(5,TimeUnit.SECONDS)).isTrue();f.clock.instant=f.clock.instant.plusSeconds(10);
                var next=queue.claim(Type.UPLOAD_VERIFY).orElseThrow(); // Must not wait for a job lock held by completion.
                release.countDown();assertThatThrownBy(()->oldCompletion.get(5,TimeUnit.SECONDS)).isInstanceOf(ExecutionException.class);
                assertThat(f.count()).isZero();assertThat(queue.complete(next,()->f.effect())).isTrue();assertThat(f.count()).isEqualTo(1);
            } finally {release.countDown();}
        }
    }
}
