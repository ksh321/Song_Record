package com.ksh321.songrecord.api.charts;

import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Global chart staging is separate from account jobs, sync and backup. */
public final class ChartStaging {
    public static final int MAX_BYTES=2*1024*1024;
    private final JdbcTemplate jdbc;private final PlatformTransactionManager manager;
    public ChartStaging(JdbcTemplate jdbc,PlatformTransactionManager manager){this.jdbc=jdbc;this.manager=manager;}
    public UUID stage(ChartScope scope,byte[] payload,Instant fetchedAt){
        Objects.requireNonNull(scope);Objects.requireNonNull(fetchedAt);
        if(payload==null || payload.length==0 || payload.length>MAX_BYTES)throw new IllegalArgumentException("Invalid staging payload size");
        var copy=payload.clone();var id=UUID.randomUUID();
        var tx=new TransactionTemplate(manager);tx.setTimeout(ChartJobDeadline.transactionSeconds());
        return tx.execute(s->{
            var locked=jdbc.query("SELECT period FROM chart_publication WHERE brand=? AND period=? FOR UPDATE",(rs,n)->rs.getString(1),scope.brand().name(),scope.period().name());
            if(locked.size()!=1)throw new IllegalStateException("Missing chart scope");
            long revision=jdbc.queryForObject("SELECT COALESCE(MAX(revision),0)+1 FROM chart_snapshot WHERE brand=? AND period=?",Long.class,scope.brand().name(),scope.period().name());
            jdbc.update("INSERT INTO chart_snapshot(id,brand,period,provider,source_url,fetched_at,revision,state,item_count) VALUES(?,?,?,?,?,?,?,'STAGING',0)",bytes(id),scope.brand().name(),scope.period().name(),ChartScope.PROVIDER,scope.sourceUri().toString(),LocalDateTime.ofInstant(fetchedAt,ZoneOffset.UTC),revision);
            jdbc.update("INSERT INTO chart_collection_payload(snapshot_id,payload) VALUES(?,?)",bytes(id),copy);
            ChartJobDeadline.check();return id;
        });
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
