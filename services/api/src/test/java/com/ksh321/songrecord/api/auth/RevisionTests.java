package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.revision.RevisionChanges.Resource;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations.Reply;
import com.ksh321.songrecord.api.web.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;

class RevisionTests {
    final IdempotencyTests f=new IdempotencyTests();
    RevisionChanges changes;UUID id=UUID.randomUUID();AtomicInteger edits=new AtomicInteger();
    final tools.jackson.databind.json.JsonMapper json=new tools.jackson.databind.json.JsonMapper();
    @BeforeEach void setup() throws Exception {
        f.setup();new ResourceDatabasePopulator(new ClassPathResource("revision-schema.sql")).populate(f.keeper);
        changes=new RevisionChanges(f.jdbc,f.access,f.manager,f.clock);
        for(String table:List.of("playlist","tag"))f.jdbc.update("INSERT INTO "+table+"(id,user_id,name) VALUES(?,?,'before')",OwnershipTests.bytes(id),OwnershipTests.bytes(f.registration.userId()));
        for(String table:List.of("song","recording"))f.jdbc.update("INSERT INTO "+table+"(id,user_id,note) VALUES(?,?,'before')",OwnershipTests.bytes(id),OwnershipTests.bytes(f.registration.userId()));
    }
    @AfterEach void close() throws Exception {f.close();}
    Reply rename(String key,long base,String name) {
        String body=json.writeValueAsString(Map.of("base_revision",base,"name",name));
        return f.mutations.execute(f.account,key,"PATCH","/v1/playlists/"+id,body,()->new Reply(200,
            json.writeValueAsString(changes.change(f.account,Resource.PLAYLIST,id.toString(),base,current->{
                edits.incrementAndGet();f.jdbc.update("UPDATE playlist SET name=? WHERE user_id=? AND id=?",name,OwnershipTests.bytes(f.registration.userId()),OwnershipTests.bytes(id));
            }))));
    }
    Map<String,Object> inTx(AccountAccess.Account account,Resource resource,String target,Long base) {
        return new TransactionTemplate(f.manager).execute(s->changes.change(account,resource,target,base,current->edits.incrementAndGet()));
    }
    @ParameterizedTest @EnumSource(Resource.class) void supportedAggregatesAdvanceExactlyOnce(Resource resource) {
        var current=inTx(f.account,resource,id.toString(),1L);
        assertThat(((Number)current.get("revision")).longValue()).isEqualTo(2);
        assertThat(current.get("id")).isEqualTo(id.toString());
        assertThat(current.get("updated_at")).isEqualTo("2026-09-24T00:00:00Z");
        assertThat(current).doesNotContainKeys("user_id","object_key","normalized_name_key");
    }
    @Test void matchingBaseEditsAndReturnsNewState() {
        var result=rename(UUID.randomUUID().toString(),1,"after");
        assertThat(result.status()).isEqualTo(200);assertThat(result.body()).contains("\"name\":\"after\"","\"revision\":2","\"deleted_at\":null");
        assertThat(edits.get()).isEqualTo(1);
    }
    @Test void staleBaseReturnsLatestStateWithoutRunningEdit() {
        rename(UUID.randomUUID().toString(),1,"winner");
        assertThatThrownBy(()->rename(UUID.randomUUID().toString(),1,"loser"))
            .isInstanceOfSatisfying(ApiException.class,e->{
                assertThat(e.status().value()).isEqualTo(409);assertThat(e.code()).isEqualTo("REVISION_CONFLICT");
                assertThat(e.details().get("current_revision")).isEqualTo(2L);
                var current=(Map<?,?>)e.details().get("current");assertThat(current.get("name")).isEqualTo("winner");
                assertThat(current.containsKey("deleted_at")).isTrue();assertThat(current.get("deleted_at")).isNull();
            });
        assertThat(edits.get()).isEqualTo(1);assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isEqualTo(1);
    }
    @Test void futureBaseAlsoConflicts() {
        assertThatThrownBy(()->rename(UUID.randomUUID().toString(),9,"wrong"))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REVISION_CONFLICT"));
        assertThat(edits.get()).isZero();
    }
    @Test void foreignAndMissingResourcesHaveNoCurrentState() {
        for(String target:List.of(id.toString(),UUID.randomUUID().toString(),"malformed"))
            assertThatThrownBy(()->inTx(f.other,Resource.PLAYLIST,target,1L))
                .isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.status().value()).isEqualTo(404);assertThat(e.details()).isEmpty();});
        assertThat(edits.get()).isZero();
    }
    @Test void baseMustBePositiveAndPresent() {
        for(Long base:Arrays.asList(null,0L,-1L))assertThatThrownBy(()->inTx(f.account,Resource.PLAYLIST,id.toString(),base))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(400));
        assertThat(edits.get()).isZero();
    }
    @Test void replayUsesReceiptBeforeNowStaleRevision() {
        var key=UUID.randomUUID().toString();var first=rename(key,1,"first");
        rename(UUID.randomUUID().toString(),2,"second");
        assertThat(rename(key,1,"first")).isEqualTo(first);assertThat(edits.get()).isEqualTo(2);
        assertThat(f.jdbc.queryForObject("SELECT name FROM playlist",String.class)).isEqualTo("second");
    }
    @Test void changedBodySameKeyIsIdempotencyConflict() {
        var key=UUID.randomUUID().toString();rename(key,1,"first");
        assertThatThrownBy(()->rename(key,2,"second")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("IDEMPOTENCY_CONFLICT"));
    }
    @Test void callbackFailureRollsBackFieldsRevisionAndReceipt() {
        assertThatThrownBy(()->f.mutations.execute(f.account,UUID.randomUUID().toString(),"PATCH","/v1/playlists/"+id,"{}",()->{
            changes.change(f.account,Resource.PLAYLIST,id.toString(),1L,current->{f.jdbc.update("UPDATE playlist SET name='wrong'");throw new IllegalStateException();});
            return new Reply(200,"{}");
        })).isInstanceOf(IllegalStateException.class);
        assertThat(f.jdbc.queryForObject("SELECT name FROM playlist",String.class)).isEqualTo("before");
        assertThat(f.jdbc.queryForObject("SELECT revision FROM playlist",Long.class)).isEqualTo(1);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
    }
    @Test void callbackCannotIncrementRevisionItself() {
        assertThatThrownBy(()->new TransactionTemplate(f.manager).execute(s->changes.change(f.account,Resource.PLAYLIST,id.toString(),1L,current->f.jdbc.update("UPDATE playlist SET revision=9"))))
            .isInstanceOf(IllegalStateException.class);
        assertThat(f.jdbc.queryForObject("SELECT revision FROM playlist",Long.class)).isEqualTo(1);
    }
    @Test void outsideTransactionAndOverflowAreRejected() {
        assertThatThrownBy(()->changes.change(f.account,Resource.PLAYLIST,id.toString(),1L,c->{})).isInstanceOf(IllegalStateException.class);
        f.jdbc.update("UPDATE playlist SET revision=?",Long.MAX_VALUE);
        assertThatThrownBy(()->inTx(f.account,Resource.PLAYLIST,id.toString(),Long.MAX_VALUE)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("REVISION_LIMIT_REACHED"));
    }
    @Test void revokedSessionCannotEdit() {
        f.sessions.logout(f.tokens.refreshToken(),f.registration.deviceId());
        assertThatThrownBy(()->inTx(f.account,Resource.PLAYLIST,id.toString(),1L)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(401));
    }
    @Test void concurrentEditsHaveOneWinnerAndOneConflict() throws Exception {
        try(var pool=Executors.newFixedThreadPool(2)) {
            var start=new CountDownLatch(1);
            java.util.function.Function<String,Callable<Integer>> task=name->()->{start.await();try{return rename(UUID.randomUUID().toString(),1,name).status();}catch(ApiException e){assertThat(e.code()).isEqualTo("REVISION_CONFLICT");return e.status().value();}};
            var a=pool.submit(task.apply("a"));var b=pool.submit(task.apply("b"));start.countDown();
            assertThat(List.of(a.get(15,TimeUnit.SECONDS),b.get(15,TimeUnit.SECONDS))).containsExactlyInAnyOrder(200,409);
            assertThat(edits.get()).isEqualTo(1);assertThat(f.jdbc.queryForObject("SELECT revision FROM playlist",Long.class)).isEqualTo(2);
        }
    }
    @RestController static class Probe {
        final RevisionTests fixture;Probe(RevisionTests fixture){this.fixture=fixture;}
        @PatchMapping("/test-revision") void change(){fixture.rename(UUID.randomUUID().toString(),1,"loser");}
    }
    @Test void httpConflictContainsCurrentValueAndRevision() throws Exception {
        rename(UUID.randomUUID().toString(),1,"winner");
        var mvc=MockMvcBuilders.standaloneSetup(new Probe(this)).setControllerAdvice(new GlobalExceptionHandler()).addFilters(new RequestIdFilter()).build();
        var response=mvc.perform(patch("/test-revision").header("X-Request-Id","revision-test")).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(409);
        var error=json.readTree(response.getContentAsString()).get("error");
        assertThat(error.get("code").asText()).isEqualTo("REVISION_CONFLICT");
        assertThat(error.get("details").get("current_revision").asLong()).isEqualTo(2);
        assertThat(error.get("details").get("current").get("name").asText()).isEqualTo("winner");
        assertThat(error.get("request_id").asText()).isEqualTo("revision-test");
    }
}
