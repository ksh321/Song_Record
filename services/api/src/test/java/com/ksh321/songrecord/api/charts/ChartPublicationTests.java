package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.nio.charset.StandardCharsets;import java.time.*;import java.util.*;import java.util.concurrent.*;
import org.junit.jupiter.api.Test;import static org.assertj.core.api.Assertions.*;
class ChartPublicationTests {
    final ChartScope scope=new ChartScope(Brand.TJ,ChartScope.Period.MONTHLY);final Clock clock=Clock.fixed(Instant.parse("2026-10-10T00:00:10Z"),ZoneOffset.UTC);
    byte[] raw(String tail){return ("[{\"brand\":\"tj\",\"no\":\"001\",\"title\":\"원본\",\"singer\":\"가수\"}"+tail+"]").getBytes(StandardCharsets.UTF_8);}
    ChartPublication publisher(ChartDatabaseFixture f){return new ChartPublication(f.jdbc,f.manager,f.validation,clock);}
    UUID stage(ChartDatabaseFixture f,byte[] raw){return f.staging.stage(scope,raw,clock.instant().minusSeconds(1));}
    byte[] pointer(ChartDatabaseFixture f){return f.jdbc.queryForObject("SELECT snapshot_id FROM chart_publication WHERE brand='TJ' AND period='MONTHLY'",byte[].class);}
    @Test void validatedRowsStateAndPointerPublishTogetherAndReplayDoesNotDuplicate()throws Exception{
        try(var f=new ChartDatabaseFixture()){var p=publisher(f);var ticket=p.begin(scope);var id=stage(f,raw(""));assertThat(p.publish(scope,ticket,id)).isTrue();assertThat(p.publish(scope,ticket,id)).isTrue();
            assertThat(pointer(f)).containsExactly(ChartStaging.bytes(id));assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_item",Integer.class)).isEqualTo(1);assertThat(f.jdbc.queryForObject("SELECT state FROM chart_snapshot WHERE id=?",String.class,ChartStaging.bytes(id))).isEqualTo("PUBLISHED");assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_publication WHERE collection_attempt_id=published_attempt_id",Integer.class)).isEqualTo(1);
        }
    }
    @Test void damagedOrEmptyReplacementKeepsExactPreviousSnapshotAndMarksStale()throws Exception{
        try(var f=new ChartDatabaseFixture()){var p=publisher(f);var first=p.begin(scope);var old=stage(f,raw(""));p.publish(scope,first,old);
            for(byte[] bad:List.of(raw(",{}"),"[]".getBytes())){var ticket=p.begin(scope);var id=stage(f,bad);assertThatThrownBy(()->p.publish(scope,ticket,id)).isInstanceOf(ChartValidation.InvalidChart.class);assertThat(pointer(f)).containsExactly(ChartStaging.bytes(old));assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_item",Integer.class)).isEqualTo(1);}
            assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_publication WHERE brand='TJ' AND period='MONTHLY' AND collection_attempt_id<>published_attempt_id",Integer.class)).isEqualTo(1);
        }
    }
    @Test void failureDuringItemBatchRollsBackInsertedRowsStateAndPointer()throws Exception{
        try(var f=new ChartDatabaseFixture()){var p=publisher(f);var first=p.begin(scope);var old=stage(f,raw(""));p.publish(scope,first,old);f.jdbc.execute("ALTER TABLE chart_item ADD CONSTRAINT reject_test_second CHECK(number<>'002')");
            var ticket=p.begin(scope);var next=stage(f,raw(",{\"brand\":\"tj\",\"no\":\"002\",\"title\":\"둘째\",\"singer\":\"가수\"}"));assertThatThrownBy(()->p.publish(scope,ticket,next)).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(pointer(f)).containsExactly(ChartStaging.bytes(old));assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_item WHERE snapshot_id=?",Integer.class,ChartStaging.bytes(next))).isZero();assertThat(f.jdbc.queryForObject("SELECT state FROM chart_snapshot WHERE id=?",String.class,ChartStaging.bytes(next))).isEqualTo("STAGING");
        }
    }
    @Test void laterStartedAttemptWinsEvenWhenOlderCollectionFinishesLater()throws Exception{
        try(var f=new ChartDatabaseFixture();var pool=Executors.newFixedThreadPool(2)){var p=publisher(f);var older=p.begin(scope);var newer=p.begin(scope);var newId=stage(f,raw(""));var oldId=stage(f,raw(""));var go=new CountDownLatch(1);
            var a=pool.submit(()->{go.await();return p.publish(scope,older,oldId);});var b=pool.submit(()->{go.await();return p.publish(scope,newer,newId);});go.countDown();assertThat(a.get(5,TimeUnit.SECONDS)).isFalse();assertThat(b.get(5,TimeUnit.SECONDS)).isTrue();assertThat(pointer(f)).containsExactly(ChartStaging.bytes(newId));assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_item",Integer.class)).isEqualTo(1);
        }
    }
    @Test void wrongScopeCannotPublishAndSourceFailureDoesNotReplacePreviousSnapshot()throws Exception{
        try(var f=new ChartDatabaseFixture()){var p=publisher(f);var first=p.begin(scope);var old=stage(f,raw(""));p.publish(scope,first,old);var ky=new ChartScope(Brand.KY,ChartScope.Period.DAILY);var ticket=p.begin(ky);var id=stage(f,raw(""));assertThatThrownBy(()->p.publish(ky,ticket,id)).isInstanceOf(IllegalArgumentException.class);
            var worker=new ChartCollection((s,d)->{throw new ChartCollection.CollectionFailure(ChartCollection.Failure.NETWORK);},f.staging::stage,clock,true,new ChartCollection.Lifecycle(){public UUID begin(ChartScope s){return p.begin(s);}public void success(ChartScope s,UUID a,UUID id){p.publish(s,a,id);}});
            assertThatThrownBy(()->worker.run(scope)).isInstanceOf(ChartCollection.CollectionFailure.class);assertThat(pointer(f)).containsExactly(ChartStaging.bytes(old));assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_publication WHERE snapshot_id IS NOT NULL",Integer.class)).isEqualTo(1);assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_publication WHERE brand='TJ' AND period='MONTHLY' AND collection_attempt_id<>published_attempt_id",Integer.class)).isEqualTo(1);assertThat(ChartJobDeadline.END.get()).isNull();
        }
    }
    @Test void expiredSharedJobBudgetPreventsAnotherDatabaseStage()throws Exception{
        try(var f=new ChartDatabaseFixture()){ChartJobDeadline.END.set(System.nanoTime()-1);try{assertThatThrownBy(()->stage(f,raw(""))).isInstanceOf(ChartCollection.CollectionFailure.class);assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM chart_snapshot",Integer.class)).isZero();}finally{ChartJobDeadline.END.remove();}}
    }
    @Test void aNewAttemptCannotRepublishAnOlderStagedRevision()throws Exception{
        try(var f=new ChartDatabaseFixture()){var p=publisher(f);var oldId=stage(f,raw(""));var newId=stage(f,raw(""));var first=p.begin(scope);assertThat(p.publish(scope,first,newId)).isTrue();var retry=p.begin(scope);assertThatThrownBy(()->p.publish(scope,retry,oldId)).isInstanceOf(IllegalStateException.class);assertThat(pointer(f)).containsExactly(ChartStaging.bytes(newId));}
    }

}
