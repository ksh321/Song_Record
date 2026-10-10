package com.ksh321.songrecord.api.charts;

import java.time.*;import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import com.ksh321.songrecord.api.web.ApiException;
import org.springframework.http.HttpStatus;

/** Read one immutable published generation. No source calls or personal data queries. */
public final class ChartQuery {
    public record Published(ChartScope scope,Instant fetchedAt,long revision,boolean stale,List<ChartValidation.Item> items){public Published{items=List.copyOf(items);}}
    private record Header(byte[] id,String provider,String source,long revision,Instant fetchedAt,int count,boolean stale){}
    private final JdbcTemplate jdbc;private final PlatformTransactionManager manager;
    public ChartQuery(JdbcTemplate jdbc,PlatformTransactionManager manager){this.jdbc=jdbc;this.manager=manager;}
    public Published read(ChartScope scope){
        var tx=new TransactionTemplate(manager);tx.setReadOnly(true);tx.setIsolationLevel(TransactionDefinition.ISOLATION_REPEATABLE_READ);tx.setTimeout(10);
        return tx.execute(status->{
            var headers=jdbc.query("SELECT s.id,s.provider,s.source_url,s.revision,s.fetched_at,s.item_count,p.collection_attempt_id,p.published_attempt_id FROM chart_publication p JOIN chart_snapshot s ON s.id=p.snapshot_id AND s.brand=p.brand AND s.period=p.period WHERE p.brand=? AND p.period=? AND s.state='PUBLISHED'",(rs,n)->new Header(rs.getBytes("id"),rs.getString("provider"),rs.getString("source_url"),rs.getLong("revision"),rs.getTimestamp("fetched_at").toLocalDateTime().toInstant(ZoneOffset.UTC),rs.getInt("item_count"),rs.getBytes("published_attempt_id")==null || !Arrays.equals(rs.getBytes("collection_attempt_id"),rs.getBytes("published_attempt_id"))),scope.brand().name(),scope.period().name());
            if(headers.size()!=1)throw unavailable();var h=headers.getFirst();
            if(!ChartScope.PROVIDER.equals(h.provider()) || !scope.sourceUri().toString().equals(h.source()) || h.revision()<1 || h.count()<1)throw unavailable();
            var items=jdbc.query("SELECT position,number,title,artist,brand,period FROM chart_item WHERE snapshot_id=? ORDER BY position",(rs,n)->{
                if(!scope.brand().name().equals(rs.getString("brand")) || !scope.period().name().equals(rs.getString("period")))throw unavailable();
                return new ChartValidation.Item(rs.getInt("position"),rs.getString("number"),rs.getString("title"),rs.getString("artist"));
            },h.id());
            if(items.size()!=h.count())throw unavailable();var numbers=new HashSet<String>();
            for(int i=0;i<items.size();i++){var item=items.get(i);if(item.position()!=i+1 || item.number()==null || !item.number().matches("[0-9]{1,20}") || !numbers.add(item.number()) || item.title()==null || item.title().isBlank() || item.artist()==null || item.artist().isBlank())throw unavailable();}
            return new Published(scope,h.fetchedAt(),h.revision(),h.stale(),items);
        });
    }
    static ApiException unavailable(){return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"CHART_SOURCE_UNAVAILABLE","이 조건의 차트 자료가 없습니다. 잠시 뒤 다시 시도해 주세요.",true,Map.of());}
}
