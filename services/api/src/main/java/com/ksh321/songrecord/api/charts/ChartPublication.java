package com.ksh321.songrecord.api.charts;

import java.time.*;import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Latest started attempt wins; rows, snapshot state and same-scope pointer publish atomically. */
public final class ChartPublication {
    private record Pointer(byte[] snapshot,byte[] attempt,byte[] publishedAttempt){}
    private final JdbcTemplate jdbc;private final PlatformTransactionManager manager;private final ChartStoredValidation validation;private final Clock clock;
    public ChartPublication(JdbcTemplate jdbc,PlatformTransactionManager manager,ChartStoredValidation validation,Clock clock){this.jdbc=jdbc;this.manager=manager;this.validation=validation;this.clock=clock;}
    private TransactionTemplate transaction(){var tx=new TransactionTemplate(manager);tx.setTimeout(ChartJobDeadline.transactionSeconds());return tx;}
    private Pointer lock(ChartScope scope){var rows=jdbc.query("SELECT snapshot_id,collection_attempt_id,published_attempt_id FROM chart_publication WHERE brand=? AND period=? FOR UPDATE",(rs,n)->new Pointer(rs.getBytes(1),rs.getBytes(2),rs.getBytes(3)),scope.brand().name(),scope.period().name());if(rows.size()!=1)throw new IllegalStateException("Missing chart publication scope");return rows.getFirst();}
    public UUID begin(ChartScope scope){var attempt=UUID.randomUUID();return transaction().execute(s->{lock(scope);jdbc.update("UPDATE chart_publication SET collection_attempt_id=? WHERE brand=? AND period=?",ChartStaging.bytes(attempt),scope.brand().name(),scope.period().name());ChartJobDeadline.check();return attempt;});}
    public boolean publish(ChartScope scope,UUID attempt,UUID id){
        Objects.requireNonNull(scope);Objects.requireNonNull(attempt);Objects.requireNonNull(id);
        return Boolean.TRUE.equals(transaction().execute(status->{
            var pointer=lock(scope);var ticket=ChartStaging.bytes(attempt);var snapshot=ChartStaging.bytes(id);
            if(!Arrays.equals(pointer.attempt(),ticket))return false;
            if(Arrays.equals(pointer.snapshot(),snapshot) && Arrays.equals(pointer.publishedAttempt(),ticket))return true;
            var staged=validation.validate(id);if(!scope.equals(staged.scope()))throw new IllegalArgumentException("Chart publication scope mismatch");
            if(pointer.snapshot()!=null && staged.revision()<jdbc.queryForObject("SELECT revision FROM chart_snapshot WHERE id=?",Long.class,pointer.snapshot()))throw new IllegalStateException("Chart revision regressed");
            var published=clock.instant();if(published.isBefore(staged.fetchedAt()))throw new IllegalStateException("Chart publication before collection");
            jdbc.batchUpdate("INSERT INTO chart_item(snapshot_id,position,brand,period,number,title,artist) VALUES(?,?,?,?,?,?,?)",staged.items(),200,(ps,item)->{ps.setBytes(1,snapshot);ps.setInt(2,item.position());ps.setString(3,scope.brand().name());ps.setString(4,scope.period().name());ps.setString(5,item.number());ps.setString(6,item.title());ps.setString(7,item.artist());});
            int changed=jdbc.update("UPDATE chart_snapshot SET state='PUBLISHED',item_count=?,published_at=? WHERE id=? AND state='STAGING'",staged.items().size(),LocalDateTime.ofInstant(published,ZoneOffset.UTC),snapshot);if(changed!=1)throw new IllegalStateException("Chart staging changed");
            jdbc.update("UPDATE chart_publication SET snapshot_id=?,published_attempt_id=? WHERE brand=? AND period=?",snapshot,ticket,scope.brand().name(),scope.period().name());ChartJobDeadline.check();return true;
        }));
    }
}
