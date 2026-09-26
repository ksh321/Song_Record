package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations.Reply;
import com.ksh321.songrecord.api.web.*;
import java.time.*;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.ResponseEntity;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

class IdempotencyTests {
    java.sql.Connection keeper; JdbcTemplate jdbc; DataSourceTransactionManager manager;
    SessionService sessions; AccountAccess access; AccountAccess.Account account,other;
    AccountRegistrationService.Registration registration; SessionService.Tokens tokens;
    IdempotentMutations mutations; SessionServiceTests.MutableClock clock;
    String key=UUID.randomUUID().toString(); AtomicInteger calls=new AtomicInteger();
    @BeforeEach void setup() throws Exception {
        var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;LOCK_TIMEOUT=10000","sa","");
        keeper=ds.getConnection();
        new ResourceDatabasePopulator(new ClassPathResource("registration-schema.sql"),new ClassPathResource("session-schema.sql"),
                new ClassPathResource("idempotency-schema.sql")).populate(keeper);
        jdbc=new JdbcTemplate(ds);manager=new DataSourceTransactionManager(ds);clock=new SessionServiceTests.MutableClock();
        var registrations=new AccountRegistrationService(jdbc,manager,clock);
        registration=registrations.register(new VerifiedProviderIdentity("GOOGLE","a"),null,"phone");
        var b=registrations.register(new VerifiedProviderIdentity("KAKAO","b"),null,"phone");
        sessions=new SessionService(jdbc,manager,clock,Duration.ofMinutes(15),Duration.ofDays(30));
        access=new AccountAccess(sessions);tokens=sessions.issue(registration);
        account=access.authenticate("Bearer "+tokens.accessToken(),registration.deviceId().toString());
        other=access.authenticate("Bearer "+sessions.issue(b).accessToken(),b.deviceId().toString());
        mutations=new IdempotentMutations(jdbc,access,manager,clock);
    }
    @AfterEach void close() throws Exception {keeper.close();}
    Reply effect() {calls.incrementAndGet();jdbc.update("UPDATE mutation_effect SET value_count=value_count+1 WHERE id=1");return new Reply(201,"{\"id\":\"created\",\"revision\":1}");}
    Reply run(String body) {return mutations.execute(account,key,"POST","/v1/songs",body,this::effect);}
    int count() {return jdbc.queryForObject("SELECT value_count FROM mutation_effect WHERE id=1",Integer.class);}
    void conflict(Runnable action) {
        assertThatThrownBy(action::run).isInstanceOfSatisfying(ApiException.class,e->{
            assertThat(e.status().value()).isEqualTo(409);assertThat(e.code()).isEqualTo("IDEMPOTENCY_CONFLICT");assertThat(e.details()).isEmpty();
        });
    }
    @Test void replayNormalizesObjectOrderWhitespaceNumbersAndEscapes() {
        var first=run("{\"b\":[1,2],\"a\":\"가\",\"n\":1.0}");
        assertThat(run(" { \"n\":1e0, \"a\":\"\\uac00\", \"b\":[1.0,2] } ")).isEqualTo(first);
        assertThat(calls.get()).isEqualTo(1);assertThat(count()).isEqualTo(1);
    }
    @Test void differentBodyArrayOrderMissingNullAndStringWhitespaceConflict() {
        run("{\"a\":[1,2],\"s\":\"x\"}");
        for(var body:new String[]{"{\"a\":[2,1],\"s\":\"x\"}","{\"a\":[1,2],\"s\":\"x\",\"n\":null}","{\"a\":[1,2],\"s\":\"x \"}"})conflict(()->run(body));
        assertThat(count()).isEqualTo(1);
    }
    @Test void routeAndMethodArePartOfHash() {
        run("{}");
        conflict(()->mutations.execute(account,key,"PATCH","/v1/songs","{}",this::effect));
        conflict(()->mutations.execute(account,key,"POST","/v1/songs/other","{}",this::effect));
        assertThat(count()).isEqualTo(1);
    }
    @Test void sameKeyIsIndependentAcrossAccounts() {
        run("{}");mutations.execute(other,key,"POST","/v1/songs","{\"different\":true}",this::effect);
        assertThat(count()).isEqualTo(2);
    }
    @Test void newServiceInstanceReplaysFromDatabase() {
        var first=run("{}");
        var restarted=new IdempotentMutations(jdbc,access,manager,clock);
        assertThat(restarted.execute(account,key,"POST","/v1/songs","{}",this::effect)).isEqualTo(first);
        assertThat(count()).isEqualTo(1);
    }
    @Test void callbackFailureRollsBackEffectAndReceiptThenRetryWorks() {
        assertThatThrownBy(()->mutations.execute(account,key,"POST","/v1/songs","{}",()->{effect();throw new IllegalStateException("failure");})).isInstanceOf(IllegalStateException.class);
        assertThat(count()).isZero();assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
        run("{}");assertThat(count()).isEqualTo(1);
    }
    @Test void receiptUpdateFailureRollsBackEffect() {
        jdbc.execute("ALTER TABLE mutation_receipt ADD CONSTRAINT injected CHECK(response_status=202)");
        assertThatThrownBy(()->run("{}")).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertThat(count()).isZero();assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
    }
    @Test void domainDuplicateKeyIsNotMistakenForReplay() {
        assertThatThrownBy(()->mutations.execute(account,key,"POST","/v1/songs","{}",()->{
            jdbc.update("INSERT INTO mutation_effect VALUES(1,5)");return effect();
        })).isInstanceOf(org.springframework.dao.DuplicateKeyException.class);
        assertThat(count()).isZero();run("{}");assertThat(count()).isEqualTo(1);
    }
    @Test void invalidRequestsDoNotRunMutation() {
        for(String body:new String[]{"", "{", "{} {}", "{\"a\":1,\"a\":2}","[NaN]"})
            assertThatThrownBy(()->run(body)).isInstanceOf(ApiException.class);
        for(String bad:new String[]{null,"","1-1-1-1-1","not-a-uuid"})
            assertThatThrownBy(()->mutations.execute(account,bad,"POST","/v1/songs","{}",this::effect)).isInstanceOf(ApiException.class);
        assertThat(calls.get()).isZero();
    }
    @Test void logoutPreventsCachedResponseReplay() {
        run("{}");sessions.logout(tokens.refreshToken(),registration.deviceId());
        assertThatThrownBy(()->run("{}")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(401));
        assertThat(calls.get()).isEqualTo(1);
    }
    @Test void receiptsRetainForNinetyDaysAndNoSecretsInReplyToString() {
        var reply=run("{}");
        var times=jdbc.queryForMap("SELECT created_at,expires_at FROM mutation_receipt");
        assertThat(jdbc.queryForObject("SELECT expires_at FROM mutation_receipt",LocalDateTime.class))
                .isEqualTo(jdbc.queryForObject("SELECT created_at FROM mutation_receipt",LocalDateTime.class).plusDays(90));
        assertThat(reply.toString()).doesNotContain("created");
    }
    @Test void noContentAndAcceptedResultsReplay() {
        for(int code:new int[]{202,204}) {
            var op=UUID.randomUUID().toString();var expected=new Reply(code,code==204?null:"{\"operation_id\":\"queued\"}");
            var one=mutations.execute(account,op,"DELETE","/v1/songs/one","{}",()->expected);
            assertThat(mutations.execute(account,op,"DELETE","/v1/songs/one","{}",()->{throw new AssertionError();})).isEqualTo(one);
        }
    }
    @Test void outerTransactionIsRejected() {
        assertThatThrownBy(()->new TransactionTemplate(manager).execute(s->run("{}"))).isInstanceOf(IllegalStateException.class);
    }
    @Test void concurrentSameRequestsExecuteOnlyOnce() throws Exception {
        try(var pool=Executors.newFixedThreadPool(2)) {
            var start=new CountDownLatch(1);
            Callable<Reply> request=()->{start.await();return run("{}");};
            var a=pool.submit(request);var b=pool.submit(request);start.countDown();
            assertThat(a.get(15,TimeUnit.SECONDS)).isEqualTo(b.get(15,TimeUnit.SECONDS));
            assertThat(count()).isEqualTo(1);assertThat(calls.get()).isEqualTo(1);
        }
    }
    @Test void concurrentDifferentBodiesProduceOneConflict() throws Exception {
        try(var pool=Executors.newFixedThreadPool(2)) {
            var start=new CountDownLatch(1);
            java.util.function.Function<String,Callable<Integer>> task=body->()->{start.await();try{return run(body).status();}catch(ApiException e){return e.status().value();}};
            var a=pool.submit(task.apply("{\"a\":1}"));var b=pool.submit(task.apply("{\"a\":2}"));start.countDown();
            assertThat(java.util.List.of(a.get(15,TimeUnit.SECONDS),b.get(15,TimeUnit.SECONDS))).containsExactlyInAnyOrder(201,409);
            assertThat(count()).isEqualTo(1);
        }
    }
    @RestController static class Probe {
        final IdempotencyTests owner;Probe(IdempotencyTests owner){this.owner=owner;}
        @PostMapping("/test-mutation") ResponseEntity<String> mutate(@RequestHeader("Idempotency-Key") String key,@RequestBody String body) {
            var reply=owner.mutations.execute(owner.account,key,"POST","/v1/songs",body,owner::effect);
            return ResponseEntity.status(reply.status()).header("Content-Type","application/json").body(reply.body());
        }
    }
    @Test void httpReplayAndConflictUseExpectedContract() throws Exception {
        var mvc=MockMvcBuilders.standaloneSetup(new Probe(this)).setControllerAdvice(new GlobalExceptionHandler())
                .addFilters(new RequestIdFilter()).build();
        String original=null;
        for(int i=0;i<2;i++) {
            var response=mvc.perform(post("/test-mutation").header("Idempotency-Key",key).contentType("application/json").content("{}")).andReturn().getResponse();
            assertThat(response.getStatus()).isEqualTo(201);
            if(original!=null)assertThat(response.getContentAsString()).isEqualTo(original);original=response.getContentAsString();
        }
        var error=mvc.perform(post("/test-mutation").header("Idempotency-Key",key).contentType("application/json").content("{\"secret\":\"private\"}")).andReturn().getResponse();
        assertThat(error.getStatus()).isEqualTo(409);assertThat(error.getContentAsString()).contains("IDEMPOTENCY_CONFLICT","request_id").doesNotContain("private",key);
        assertThat(count()).isEqualTo(1);
    }
}
