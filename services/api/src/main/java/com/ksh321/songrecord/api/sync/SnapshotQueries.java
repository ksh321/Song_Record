package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.MultiValueMap;
import tools.jackson.databind.json.JsonMapper;

public final class SnapshotQueries {
    public record Reply(int status,Map<String,Object> body) {
        @Override public String toString(){return "SnapshotQueryReply[REDACTED]";}
    }
    private record Header(String status,int schema,Long cursor,Instant captured,Instant ready,Instant expires,String hash) {}
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final SnapshotPages pages;
    private final Clock clock;
    private final JsonMapper json=new JsonMapper();
    public SnapshotQueries(JdbcTemplate jdbc,AccountAccess access,SnapshotPages pages,Clock clock){this.jdbc=jdbc;this.access=access;this.pages=pages;this.clock=clock;}
    public Reply get(String authorization,String device,String token,MultiValueMap<String,String> query) {
        var account=access.authenticate(authorization,device);UUID id;
        if(token==null)throw invalid();
        try{id=UUID.fromString(token);if(!id.toString().equals(token))throw invalid();}catch(IllegalArgumentException e){throw invalid();}
        if(query.keySet().stream().anyMatch(k->!Set.of("entity","cursor","limit").contains(k))
                ||query.values().stream().anyMatch(v->v==null||v.size()!=1||v.getFirst()==null))throw invalid();
        if(!query.containsKey("entity")){
            if(!query.isEmpty())throw invalid();return status(account,id);
        }
        SnapshotPages.Entity entity;Integer limit=null;
        try{
            entity=SnapshotPages.Entity.valueOf(query.getFirst("entity"));
            if(query.containsKey("limit")) {
                String value=query.getFirst("limit");if(!value.matches("[1-9][0-9]{0,2}"))throw invalid();limit=Integer.valueOf(value);
            }
        }catch(IllegalArgumentException e){throw invalid();}
        // Distinguish a cleaned, previously issued token from an unknown/foreign one.
        header(access.revalidate(account).userId(),id);
        var page=pages.read(account,id,entity,query.getFirst("cursor"),limit);
        var body=new LinkedHashMap<String,Object>();
        body.put("snapshot_token",id.toString());body.put("snapshot_cursor",page.snapshotCursor());
        body.put("expires_at",page.expiresAt().toString());body.put("entity",entity.name());
        body.put("entries",page.entries().stream().map(entry->Map.of("ordinal",entry.ordinal(),"resource_id",entry.resourceId().toString(),"payload",json.readTree(entry.payload()))).toList());
        body.put("next_cursor",page.nextCursor());
        return new Reply(200,Collections.unmodifiableMap(body));
    }
    private Reply status(AccountAccess.Account account,UUID token) {
        UUID owner=access.revalidate(account).userId();var header=header(owner,token);
        var body=new LinkedHashMap<String,Object>();body.put("snapshot_token",token.toString());body.put("status",header.status);body.put("schema_version",header.schema);
        if(header.status.equals("READY")) {
            var counts=new TreeMap<String,Long>();for(var entity:SnapshotPages.Entity.values())counts.put(entity.name(),0L);
            jdbc.query("SELECT entity,COUNT(*) FROM snapshot_entry WHERE snapshot_id=? GROUP BY entity",
                    (org.springframework.jdbc.core.RowCallbackHandler)rs->counts.put(rs.getString(1),rs.getLong(2)),bytes(token));
            body.put("snapshot_cursor",header.cursor);body.put("captured_at",header.captured.toString());body.put("ready_at",header.ready.toString());
            body.put("expires_at",header.expires.toString());body.put("manifest_hash",header.hash);body.put("entity_counts",Collections.unmodifiableMap(counts));
        }
        if(!access.revalidate(account).userId().equals(owner))throw failure(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION");
        if(!header.equals(header(owner,token)))throw failure(HttpStatus.CONFLICT,"SNAPSHOT_STATE_CHANGED");
        return new Reply(header.status.equals("READY")?200:202,Collections.unmodifiableMap(body));
    }
    private Header header(UUID owner,UUID token) {
        var rows=jdbc.query("SELECT status,schema_version,snapshot_cursor,captured_at,ready_at,expires_at,manifest_hash FROM snapshot_header WHERE user_id=? AND id=? AND purpose='SYNC'",
                (rs,n)->new Header(rs.getString(1),rs.getInt(2),rs.getObject(3,Long.class),instant(rs.getTimestamp(4)),instant(rs.getTimestamp(5)),instant(rs.getTimestamp(6)),rs.getString(7)),bytes(owner),bytes(token));
        if(rows.isEmpty()) {
            var issued=jdbc.query("SELECT 1 FROM mutation_receipt WHERE user_id=? AND response_status=202 AND JSON_UNQUOTE(JSON_EXTRACT(response_body,'$.snapshot_token'))=? LIMIT 1",
                    (rs,n)->1,bytes(owner),token.toString());
            throw failure(issued.isEmpty()?HttpStatus.NOT_FOUND:HttpStatus.GONE,issued.isEmpty()?"SNAPSHOT_NOT_FOUND":"SNAPSHOT_EXPIRED");
        }
        var header=rows.getFirst();
        if(header.status.equals("EXPIRED")||header.expires!=null&&!clock.instant().isBefore(header.expires))throw failure(HttpStatus.GONE,"SNAPSHOT_EXPIRED");
        if(header.status.equals("FAILED"))throw failure(HttpStatus.CONFLICT,"SNAPSHOT_FAILED");
        return header;
    }
    private static Instant instant(java.sql.Timestamp value){return value==null?null:value.toLocalDateTime().toInstant(ZoneOffset.UTC);}
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static ApiException invalid(){return failure(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR");}
    private static ApiException failure(HttpStatus status,String code){return new ApiException(status,code,"스냅샷 상태와 조회 조건을 확인해 주세요.",false,Map.of());}
}
