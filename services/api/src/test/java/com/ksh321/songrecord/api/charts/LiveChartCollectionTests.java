package com.ksh321.songrecord.api.charts;

import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import static org.assertj.core.api.Assertions.*;

class LiveChartCollectionTests {
    @Test void activationRequiresBothFlagsAndAnOperationalProfile() throws Exception {
        try(var f=new ChartDatabaseFixture()){
            var runner=new ApplicationContextRunner().withUserConfiguration(LiveChartCollectionConfiguration.class)
                    .withBean(JdbcTemplate.class,()->f.jdbc).withBean(PlatformTransactionManager.class,()->f.manager);
            runner.withPropertyValues("spring.profiles.active=staging").run(c->assertThat(c).doesNotHaveBean(ChartCollection.class));
            runner.withPropertyValues("spring.profiles.active=staging","songrecord.charts.live-enabled=true").run(c->assertThat(c).doesNotHaveBean(ChartCollection.class));
            runner.withPropertyValues("spring.profiles.active=staging","songrecord.charts.storage-approved=true").run(c->assertThat(c).doesNotHaveBean(ChartCollection.class));
            for(String profile:List.of("dev","bootstrap","staging,dev","prod,bootstrap")){
                runner.withPropertyValues("spring.profiles.active="+profile,"songrecord.charts.live-enabled=true","songrecord.charts.storage-approved=true")
                        .run(c->assertThat(c).doesNotHaveBean(ChartCollection.class));
            }
            runner.withPropertyValues("spring.profiles.active=staging","songrecord.charts.live-enabled=true","songrecord.charts.storage-approved=true")
                    .run(c->{assertThat(c).hasSingleBean(ChartCollection.class);assertThat(c).hasBean("liveChartCollection");assertThat(c).doesNotHaveBean(LiveChartCollectionScheduling.class);});
        }
    }

    @Test void sixScopesPublishAndOneFailedCollectionKeepsItsOwnLastResult() throws Exception {
        try(var f=new ChartDatabaseFixture()){
            var clock=Clock.fixed(Instant.parse("2026-10-19T00:00:00Z"),ZoneOffset.UTC);
            var publication=new ChartPublication(f.jdbc,f.manager,f.validation,clock);
            var fail=new AtomicBoolean(false);
            try(var collection=ChartCollection.approvedLive((scope,remaining)->{
                if(fail.get() && scope.brand()==Brand.TJ && scope.period()==ChartScope.Period.DAILY)
                    throw new ChartCollection.CollectionFailure(ChartCollection.Failure.NETWORK);
                return ("[{\"brand\":\""+scope.providerBrand()+"\",\"no\":\"00123\",\"title\":\"검사 곡\",\"singer\":\"검사 가수\"}]").getBytes(StandardCharsets.UTF_8);
            },(scope,payload,time)->{var id=f.staging.stage(scope,payload,time);f.validation.validate(id);return id;},clock,new ChartCollection.Lifecycle(){
                public UUID begin(ChartScope s){return publication.begin(s);}
                public void success(ChartScope s,UUID attempt,UUID staged){publication.publish(s,attempt,staged);}
            })){
                var schedule=new LiveChartCollectionScheduling(collection,21600000,5000);
                var query=new ChartQuery(f.jdbc,f.manager);schedule.tick();
                assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_publication WHERE snapshot_id IS NOT NULL",Integer.class)).isEqualTo(6);
                for(var brand:Brand.values())for(var period:ChartScope.Period.values()){
                    var result=query.read(new ChartScope(brand,period));assertThat(result.stale()).isFalse();assertThat(result.items()).hasSize(1);
                    assertThat(result.items().getFirst().number()).isEqualTo("00123");
                }
                var scope=new ChartScope(Brand.TJ,ChartScope.Period.DAILY);var previous=query.read(scope);
                fail.set(true);schedule.tick();var kept=query.read(scope);
                assertThat(kept.revision()).isEqualTo(previous.revision());assertThat(kept.fetchedAt()).isEqualTo(previous.fetchedAt());assertThat(kept.stale()).isTrue();
                assertThat(query.read(new ChartScope(Brand.KY,ChartScope.Period.MONTHLY)).revision()).isGreaterThan(previous.revision());
            }
        }
    }

    @Test void malformedLiveResponseCannotReplacePublishedItems() throws Exception {
        try(var f=new ChartDatabaseFixture()){
            var config=new LiveChartCollectionConfiguration();var publication=config.chartPublication(f.jdbc,f.manager,f.validation);
            var bad=new AtomicBoolean(false);var scope=new ChartScope(Brand.TJ,ChartScope.Period.MONTHLY);
            try(var collection=ChartCollection.approvedLive((s,left)->(bad.get()?"[]":"[{\"brand\":\"tj\",\"no\":\"00123\",\"title\":\"검사 곡\",\"singer\":\"검사 가수\"}]").getBytes(StandardCharsets.UTF_8),
                    (s,p,t)->{var id=f.staging.stage(s,p,t);f.validation.validate(id);return id;},Clock.systemUTC(),new ChartCollection.Lifecycle(){
                        public UUID begin(ChartScope s){return publication.begin(s);}
                        public void success(ChartScope s,UUID a,UUID id){publication.publish(s,a,id);}
                    })){
                collection.run(scope);var query=new ChartQuery(f.jdbc,f.manager);var old=query.read(scope);bad.set(true);
                assertThatThrownBy(()->collection.run(scope)).isInstanceOf(RuntimeException.class);
                var current=query.read(scope);assertThat(current.revision()).isEqualTo(old.revision());assertThat(current.items()).isEqualTo(old.items());assertThat(current.stale()).isTrue();
            }
        }
    }

    @Test void unsafePollingIntervalsAreRejected(){
        try(var collection=ChartCollection.approvedLive((s,left)->new byte[0],(s,p,t)->UUID.randomUUID(),Clock.systemUTC(),new ChartCollection.Lifecycle(){
            public UUID begin(ChartScope s){return UUID.randomUUID();}public void success(ChartScope s,UUID a,UUID id){}
        })){
            for(long delay:new long[]{0,299999,86400001})assertThatThrownBy(()->new LiveChartCollectionScheduling(collection,delay,5000)).isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(()->new LiveChartCollectionScheduling(collection,21600000,0)).isInstanceOf(IllegalArgumentException.class);
        }
    }
}
