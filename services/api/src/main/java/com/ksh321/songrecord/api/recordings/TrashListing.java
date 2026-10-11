package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.ZoneOffset;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Account-scoped keyset over immutable deletion snapshots, never object keys. */
public final class TrashListing {
    private final JdbcTemplate db;private final AccountAccess access;private final TransactionTemplate read;
    public TrashListing(JdbcTemplate db,AccountAccess access){this.db=db;this.access=access;read=new TransactionTemplate(new DataSourceTransactionManager(db.getDataSource()));read.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);}
    public Map<String,Object> list(String auth,String device,String cursor,int limit){
        var account=access.authenticate(auth,device);if(limit<1 || limit>100)throw invalid();UUID after=null;
        if(cursor!=null){try{after=UUID.fromString(cursor);if(!after.toString().equals(cursor))throw new IllegalArgumentException();}catch(IllegalArgumentException e){throw invalid();}}
        UUID next=after;
        return read.execute(status->{
            UUID owner=access.revalidate(account).userId();LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));
            String condition="";var arguments=new ArrayList<Object>();arguments.add(bytes(owner));
            if(next!=null){var row=db.queryForList("SELECT deleted_at FROM deletion_batch WHERE user_id=? AND id=?",bytes(owner),bytes(next));if(row.isEmpty())throw invalid();condition=" AND (b.deleted_at<? OR (b.deleted_at=? AND b.id<?))";arguments.add(row.getFirst().get("deleted_at"));arguments.add(row.getFirst().get("deleted_at"));arguments.add(bytes(next));}
            arguments.add(limit+1);
            String pending=" AND EXISTS(SELECT 1 FROM deletion_item d LEFT JOIN song s ON d.entity_type='SONG' AND s.user_id=d.user_id AND s.id=d.entity_id LEFT JOIN recording r ON d.entity_type='RECORDING' AND r.user_id=d.user_id AND r.id=d.entity_id WHERE d.user_id=b.user_id AND d.batch_id=b.id AND ((s.lifecycle_state IN ('TRASHED','PURGE_PENDING') AND s.deleted_at=b.deleted_at) OR (r.lifecycle_state IN ('TRASHED','PURGE_PENDING') AND r.deleted_at=b.deleted_at)))";
            var rows=db.queryForList("SELECT b.id,b.mode,b.deleted_at,b.purge_after,COALESCE(w.revision,1) AS revision FROM deletion_batch b LEFT JOIN deletion_batch_work w ON w.user_id=b.user_id AND w.batch_id=b.id WHERE b.user_id=?"+pending+condition+" ORDER BY b.deleted_at DESC,b.id DESC LIMIT ?",arguments.toArray());
            boolean more=rows.size()>limit;var result=new ArrayList<Map<String,Object>>();
            for(var row:rows.subList(0,Math.min(limit,rows.size()))){UUID batch=uuid((byte[])row.get("id"));var value=new LinkedHashMap<String,Object>();value.put("batch_id",batch.toString());value.put("mode",row.get("mode"));value.put("revision",row.get("revision"));for(String key:List.of("deleted_at","purge_after"))value.put(key,TrashRestoration.time(row.get(key)).toInstant(ZoneOffset.UTC).toString());
                var items=new ArrayList<Map<String,Object>>();for(var item:db.queryForList("SELECT entity_type,entity_id FROM deletion_item WHERE user_id=? AND batch_id=? ORDER BY entity_type,entity_id",bytes(owner),bytes(batch))){
                    var member=new LinkedHashMap<String,Object>();member.put("entity_type",item.get("entity_type"));member.put("id",uuid((byte[])item.get("entity_id")).toString());
                    String type=(String)item.get("entity_type");
                    if(List.of("SONG","RECORDING").contains(type)){
                        String table=type.equals("SONG")?"song":"recording";
                        var states=db.queryForList("SELECT lifecycle_state FROM "+table+" WHERE user_id=? AND id=?",bytes(owner),item.get("entity_id"));
                        if(!states.isEmpty())member.put("lifecycle_state",states.getFirst().get("lifecycle_state"));
                    }
                    items.add(member);
                }value.put("items",items);result.add(value);
            }
            var response=new LinkedHashMap<String,Object>();response.put("items",result);response.put("next_cursor",more?result.getLast().get("batch_id"):null);return response;
        });
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","휴지통 페이지 범위를 확인해 주세요.",false,Map.of());}
}
