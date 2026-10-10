package com.ksh321.songrecord.api.charts;

import java.time.*;import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;

/** Read the whole scoped staging payload; no rows or publication pointer change on failure. */
public final class ChartStoredValidation {
    public record Staged(UUID id,ChartScope scope,Instant fetchedAt,long revision,List<ChartValidation.Item> items){public Staged{items=List.copyOf(items);}}
    private final JdbcTemplate jdbc;private final ChartValidation validation;
    public ChartStoredValidation(JdbcTemplate jdbc,ChartValidation validation){this.jdbc=jdbc;this.validation=validation;}
    public Staged validate(UUID id){
        var rows=jdbc.query("SELECT s.brand,s.period,s.provider,s.source_url,s.fetched_at,s.revision,s.state,p.payload FROM chart_snapshot s JOIN chart_collection_payload p ON p.snapshot_id=s.id WHERE s.id=?",(rs,n)->{
            var scope=ChartScope.parse(rs.getString("brand"),rs.getString("period"));
            if(!"STAGING".equals(rs.getString("state")) || !ChartScope.PROVIDER.equals(rs.getString("provider")) || !scope.sourceUri().toString().equals(rs.getString("source_url")))throw new IllegalStateException("Invalid staged chart metadata");
            return new Staged(id,scope,rs.getTimestamp("fetched_at").toLocalDateTime().toInstant(ZoneOffset.UTC),rs.getLong("revision"),validation.validate(scope,rs.getBytes("payload")));
        },ChartStaging.bytes(Objects.requireNonNull(id)));
        if(rows.size()!=1)throw new IllegalStateException("Missing staged chart payload");return rows.getFirst();
    }
}
