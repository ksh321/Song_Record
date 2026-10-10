package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.nio.charset.StandardCharsets;import java.time.*;import java.util.*;import java.util.concurrent.*;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static org.assertj.core.api.Assertions.*;
/** Invoked by existing real-MySQL CI test after V9-to-latest upgrade, only on disposable CI DB. */
public final class ChartMySqlDatabaseChecks {
    public static void verify(JdbcTemplate jdbc)throws Exception{
        var scope=new ChartScope(Brand.TJ,ChartScope.Period.MONTHLY);var manager=new DataSourceTransactionManager(jdbc.getDataSource());var staging=new ChartStaging(jdbc,manager);var validation=new ChartStoredValidation(jdbc,new ChartValidation());var publication=new ChartPublication(jdbc,manager,validation,Clock.systemUTC());
        int changes=jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class);String raw="[{\"brand\":\"tj\",\"no\":\"001\",\"title\":\"검사 곡\",\"singer\":\"가수\"}]";
        var ticket=publication.begin(scope);var first=staging.stage(scope,raw.getBytes(StandardCharsets.UTF_8),Instant.now().minusSeconds(1));assertThat(publication.publish(scope,ticket,first)).isTrue();assertThat(publication.publish(scope,ticket,first)).isTrue();
        assertThat(jdbc.queryForObject("SELECT snapshot_id FROM chart_publication WHERE brand='TJ' AND period='MONTHLY'",byte[].class)).containsExactly(ChartStaging.bytes(first));
        jdbc.execute("CREATE TRIGGER reject_chart_second BEFORE INSERT ON chart_item FOR EACH ROW BEGIN IF NEW.number='002' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='fixture chart item rejection'; END IF; END");
        try{var failTicket=publication.begin(scope);String pair=raw.substring(0,raw.length()-1)+",{\"brand\":\"tj\",\"no\":\"002\",\"title\":\"둘째\",\"singer\":\"가수\"}]";var bad=staging.stage(scope,pair.getBytes(StandardCharsets.UTF_8),Instant.now().minusSeconds(1));assertThatThrownBy(()->publication.publish(scope,failTicket,bad)).isInstanceOf(org.springframework.dao.DataAccessException.class);assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM chart_item WHERE snapshot_id=?",Integer.class,ChartStaging.bytes(bad))).isZero();assertThat(jdbc.queryForObject("SELECT state FROM chart_snapshot WHERE id=?",String.class,ChartStaging.bytes(bad))).isEqualTo("STAGING");assertThat(jdbc.queryForObject("SELECT snapshot_id FROM chart_publication WHERE brand='TJ' AND period='MONTHLY'",byte[].class)).containsExactly(ChartStaging.bytes(first));}finally{jdbc.execute("DROP TRIGGER reject_chart_second");}
        var older=publication.begin(scope);var newer=publication.begin(scope);var newId=staging.stage(scope,raw.getBytes(StandardCharsets.UTF_8),Instant.now().minusSeconds(1));var oldId=staging.stage(scope,raw.getBytes(StandardCharsets.UTF_8),Instant.now().minusSeconds(1));
        try(var pool=Executors.newFixedThreadPool(2)){var go=new CountDownLatch(1);var a=pool.submit(()->{go.await();return publication.publish(scope,older,oldId);});var b=pool.submit(()->{go.await();return publication.publish(scope,newer,newId);});go.countDown();assertThat(a.get(10,TimeUnit.SECONDS)).isFalse();assertThat(b.get(10,TimeUnit.SECONDS)).isTrue();}
        assertThat(jdbc.queryForObject("SELECT snapshot_id FROM chart_publication WHERE brand='TJ' AND period='MONTHLY'",byte[].class)).containsExactly(ChartStaging.bytes(newId));
        var ky=new ChartScope(Brand.KY,ChartScope.Period.DAILY);var kyTicket=publication.begin(ky);var kyId=staging.stage(ky,raw.replace("tj","kumyoung").getBytes(StandardCharsets.UTF_8),Instant.now().minusSeconds(1));assertThat(publication.publish(ky,kyTicket,kyId)).isTrue();
        assertThatThrownBy(()->jdbc.update("UPDATE chart_publication SET snapshot_id=NULL WHERE brand='TJ' AND period='MONTHLY'")).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThatThrownBy(()->jdbc.update("UPDATE chart_publication SET published_attempt_id=? WHERE brand='TJ' AND period='MONTHLY'",ChartStaging.bytes(UUID.randomUUID()))).isInstanceOf(org.springframework.dao.DataAccessException.class);
assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM change_log",Integer.class)).isEqualTo(changes);
    }
}
