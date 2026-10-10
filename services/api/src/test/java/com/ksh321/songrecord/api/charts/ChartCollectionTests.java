package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import static org.assertj.core.api.Assertions.*;

class ChartCollectionTests {
    final ChartScope scope=new ChartScope(Brand.TJ,ChartScope.Period.MONTHLY);
    final Clock clock=Clock.fixed(Instant.parse("2026-10-10T00:00:00Z"),ZoneOffset.UTC);
    @Test void entirePayloadStagesAtomicallyAndPublicationPointerStaysUnchanged() throws Exception {
        var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL","sa","");
        try(var keeper=ds.getConnection()){
            var jdbc=new JdbcTemplate(ds);
            jdbc.execute("CREATE TABLE chart_publication(brand VARCHAR(2),period VARCHAR(8),snapshot_id BINARY(16),PRIMARY KEY(brand,period))");
            jdbc.execute("CREATE TABLE chart_snapshot(id BINARY(16) PRIMARY KEY,brand VARCHAR(2),period VARCHAR(8),provider VARCHAR(16),source_url VARCHAR(512),fetched_at TIMESTAMP,revision BIGINT,state VARCHAR(16),item_count INT,UNIQUE(brand,period,revision))");
            jdbc.execute("CREATE TABLE chart_collection_payload(snapshot_id BINARY(16) PRIMARY KEY,payload BLOB NOT NULL,FOREIGN KEY(snapshot_id) REFERENCES chart_snapshot(id))");
            var existing=UUID.randomUUID();jdbc.update("INSERT INTO chart_publication VALUES('TJ','MONTHLY',?)",ChartStaging.bytes(existing));
            var staging=new ChartStaging(jdbc,new DataSourceTransactionManager(ds));byte[] raw="[{\"no\":\"00123\"}]".getBytes(StandardCharsets.UTF_8);
            var worker=new ChartCollection((s,remaining)->raw,staging::stage,clock,true);
            var first=worker.run(scope);worker.run(scope);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM chart_snapshot",Integer.class)).isEqualTo(2);
            assertThat(jdbc.queryForObject("SELECT MAX(revision) FROM chart_snapshot",Long.class)).isEqualTo(2);
            assertThat(jdbc.queryForObject("SELECT state FROM chart_snapshot WHERE id=?",String.class,ChartStaging.bytes(first))).isEqualTo("STAGING");
            assertThat(jdbc.queryForObject("SELECT payload FROM chart_collection_payload WHERE snapshot_id=?",byte[].class,ChartStaging.bytes(first))).containsExactly(raw);
            assertThat(jdbc.queryForObject("SELECT snapshot_id FROM chart_publication",byte[].class)).containsExactly(ChartStaging.bytes(existing));
            jdbc.execute("DROP TABLE chart_collection_payload");
            assertThatThrownBy(()->staging.stage(scope,raw,clock.instant())).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM chart_snapshot",Integer.class)).isEqualTo(2);
            assertThat(jdbc.queryForObject("SELECT snapshot_id FROM chart_publication",byte[].class)).containsExactly(ChartStaging.bytes(existing));

        }
    }
    @Test void failureRetriesOnceWithinSharedDeadlineButNeverWritesPartialPayload(){
        var calls=new AtomicInteger();var saves=new AtomicInteger();
        var worker=new ChartCollection((s,remaining)->{assertThat(remaining).isPositive().isLessThanOrEqualTo(Duration.ofSeconds(30));if(calls.incrementAndGet()==1)throw new ChartCollection.CollectionFailure(ChartCollection.Failure.NETWORK);return new byte[]{1};},(s,p,t)->{saves.incrementAndGet();return UUID.randomUUID();},clock,true);
        worker.run(scope);assertThat(calls).hasValue(2);assertThat(saves).hasValue(1);
        var failing=new ChartCollection((s,d)->{throw new ChartCollection.CollectionFailure(ChartCollection.Failure.NETWORK);},(s,p,t)->{throw new AssertionError("must not stage failed data");},clock,true);
        assertThatThrownBy(()->failing.run(scope)).isInstanceOf(ChartCollection.CollectionFailure.class);
    }
    @Test void liveCollectionIsBlockedBeforeFetchingAndOversizeNeverStages(){
        var worker=new ChartCollection((s,d)->{throw new AssertionError("live source must stay off");},(s,p,t)->UUID.randomUUID(),clock,false);
        assertThatThrownBy(()->worker.run(scope)).isInstanceOfSatisfying(ChartCollection.CollectionFailure.class,e->assertThat(e.kind()).isEqualTo(ChartCollection.Failure.LIVE_STORAGE_NOT_APPROVED));
        var tooLarge=new ChartCollection((s,d)->new byte[ChartStaging.MAX_BYTES+1],(s,p,t)->{throw new AssertionError("must not stage oversized data");},clock,true);
        assertThatThrownBy(()->tooLarge.run(scope)).isInstanceOf(ChartCollection.CollectionFailure.class);
    }
    @Test void atMostTwoBackgroundSourcesRunAndSlotsRecoverAfterCompletion() throws Exception {
        var entered=new CountDownLatch(2);var release=new CountDownLatch(1);var pool=Executors.newFixedThreadPool(2);
        var worker=new ChartCollection((s,d)->{entered.countDown();try{assertThat(release.await(5,TimeUnit.SECONDS)).isTrue();}catch(InterruptedException e){Thread.currentThread().interrupt();throw new RuntimeException();}return new byte[]{1};},(s,p,t)->UUID.randomUUID(),clock,true);
        try{var a=pool.submit(()->worker.run(scope));var b=pool.submit(()->worker.run(scope));assertThat(entered.await(5,TimeUnit.SECONDS)).isTrue();assertThatThrownBy(()->worker.run(scope)).isInstanceOfSatisfying(ChartCollection.CollectionFailure.class,e->assertThat(e.kind()).isEqualTo(ChartCollection.Failure.BUSY));release.countDown();a.get();b.get();worker.run(scope);}finally{release.countDown();pool.shutdownNow();}
    }
    @Test void hungSourceTimesOutAndCannotStageLater() throws Exception {
        var interrupted=new CountDownLatch(1);var saves=new AtomicInteger();
        var worker=new ChartCollection((s,d)->{try{Thread.sleep(5000);}catch(InterruptedException e){interrupted.countDown();Thread.currentThread().interrupt();}return new byte[]{1};},(s,p,t)->{saves.incrementAndGet();return UUID.randomUUID();},clock,true,Duration.ofMillis(100));
        long start=System.nanoTime();
        assertThatThrownBy(()->worker.run(scope)).isInstanceOfSatisfying(ChartCollection.CollectionFailure.class,e->assertThat(e.kind()).isEqualTo(ChartCollection.Failure.TIMEOUT));
        assertThat(Duration.ofNanos(System.nanoTime()-start)).isLessThan(Duration.ofSeconds(2));
        assertThat(interrupted.await(2,TimeUnit.SECONDS)).isTrue();assertThat(saves).hasValue(0);
    }
    @Test void fetchingInsideDatabaseTransactionIsRejected(){
        org.springframework.transaction.support.TransactionSynchronizationManager.setActualTransactionActive(true);
        try{var worker=new ChartCollection((s,d)->{throw new AssertionError("No source call in a transaction");},(s,p,t)->UUID.randomUUID(),clock,true);
            assertThatThrownBy(()->worker.run(scope)).isInstanceOf(IllegalStateException.class);
        }finally{org.springframework.transaction.support.TransactionSynchronizationManager.setActualTransactionActive(false);}
    }

    @Test void fixtureCollectionRequiresExplicitDevelopmentOnlySwitch(){
        for(String profiles:List.of("", "prod", "dev,prod", "dev,bootstrap", "dev")){
            for(boolean enabled:List.of(false,true)){
                try(var context=new org.springframework.context.annotation.AnnotationConfigApplicationContext()){
                    if(!profiles.isEmpty())context.getEnvironment().setActiveProfiles(profiles.split(","));
                    context.getEnvironment().getPropertySources().addFirst(new org.springframework.core.env.MapPropertySource("fixture",Map.of("songrecord.charts.fixture-enabled",String.valueOf(enabled))));
                    var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID(),"sa","");
                    context.registerBean(JdbcTemplate.class,()->new JdbcTemplate(ds));
                    context.registerBean(org.springframework.transaction.PlatformTransactionManager.class,()->new DataSourceTransactionManager(ds));
                    context.register(ChartCollectionConfiguration.class);context.refresh();
                    assertThat(context.getBeansOfType(ChartCollection.class)).hasSize(profiles.equals("dev") && enabled?1:0);
                }
            }
        }
    }

}
