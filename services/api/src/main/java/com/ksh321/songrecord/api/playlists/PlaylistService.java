package com.ksh321.songrecord.api.playlists;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.*;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.revision.*;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.MultiValueMap;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Owned playlists persist across dates and sessions; deletion never edits songs or recordings. */
public final class PlaylistService {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final CreationGuard guard;private final RevisionChanges revisions;private final AccountChanges changes;
    private final KeysetPages pages;private final Clock clock;private final com.ksh321.songrecord.api.jobs.JobQueue jobs;
    public PlaylistService(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,RevisionChanges revisions,AccountChanges changes,KeysetPages pages,Clock clock,com.ksh321.songrecord.api.jobs.JobQueue jobs){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.guard=guard;this.revisions=revisions;this.changes=changes;this.pages=pages;this.clock=clock;this.jobs=jobs;
    }
    public IdempotentMutations.Reply create(String auth,String device,String op,String body){
        var account=access.authenticate(auth,device);var root=parse(body,Set.of("id","name"));UUID id=uuid(text(root.get("id")),false);String name=name(root.get("name"));UUID owner=account.principal().userId();
        try{return mutations.execute(account,op,"POST","/v1/playlists",body,()->{
            var result=guard.create(account,CreationGuard.Resource.PLAYLIST,id,()->changes.write(account,()->{

                var now=now();jdbc.update("INSERT INTO playlist(id,user_id,name,revision,created_at,updated_at) VALUES(?,?,?,1,?,?)",bytes(id),bytes(owner),name,now,now);
                return batch(id,201,snapshot(owner,id));
            }).value());
            if(result.created())return result.value();
            if(result.existing().state().equals("DELETED"))throw conflict("PLAYLIST_DELETED","삭제한 목록은 다시 생성할 수 없습니다.");
            return new IdempotentMutations.Reply(200,JSON.writeValueAsString(snapshot(owner,id)));
        });}catch(DuplicateKeyException e){throw conflict("PLAYLIST_ID_CONFLICT","목록 식별자를 확인해 주세요.");}
    }
    public IdempotentMutations.Reply rename(String auth,String device,String op,String id,String body){return edit(auth,device,op,id,body,false);}
    public IdempotentMutations.Reply delete(String auth,String device,String op,String id,String body){return edit(auth,device,op,id,body,true);}
    private IdempotentMutations.Reply edit(String auth,String device,String op,String rawId,String body,boolean delete){
        var account=access.authenticate(auth,device);UUID id=uuid(rawId,true),owner=account.principal().userId();
        var root=parse(body,delete?Set.of("base_revision"):Set.of("base_revision","name"));long revision=revision(root.get("base_revision"));String name=delete?null:name(root.get("name"));
        return mutations.execute(account,op,delete?"DELETE":"PATCH","/v1/playlists/"+id,body,()->{
            var locked=revisionsReadDeleted(account,id);
            if(locked!=null){
                if(!delete)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");
                return new IdempotentMutations.Reply(200,JSON.writeValueAsString(deletion(locked)));
            }
            return changes.write(account,()->{
            var updated=revisions.change(account,RevisionChanges.Resource.PLAYLIST,id.toString(),revision,current->{
                if(current.get("deleted_at")!=null)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");
                if(delete){
                    var deletedAt=now();
                    long next=((Number)current.get("revision")).longValue()+1;
                    jdbc.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision,purged_at) VALUES(?,?,'PLAYLIST',?,?,?)",bytes(UUID.randomUUID()),bytes(owner),bytes(id),next,deletedAt);
                    for(byte[] child:jdbc.query("SELECT id FROM playlist_item WHERE user_id=? AND playlist_id=?",(rs,n)->rs.getBytes(1),bytes(owner),bytes(id))) jdbc.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision) VALUES(?,?,'PLAYLIST_ITEM',?,?)",bytes(UUID.randomUUID()),bytes(owner),child,next);
                    jdbc.update("UPDATE playlist SET deleted_at=? WHERE user_id=? AND id=?",deletedAt,bytes(owner),bytes(id));
                }
                else{
                    jdbc.update("UPDATE playlist SET name=? WHERE user_id=? AND id=?",name,bytes(owner),bytes(id));
                }
            });
            if(delete) jobs.enqueue(account,com.ksh321.songrecord.api.jobs.JobQueue.Type.PLAYLIST_CLEANUP,id,UUID.fromString(op),"{}");
            return batch(id,200,updated);
        }).value();});
    }
    private Map<String,Object> revisionsReadDeleted(AccountAccess.Account account,UUID id){
        // Lock order: account sync precedes aggregate. This also serializes concurrent deletes.
        com.ksh321.songrecord.api.locking.LockOrder.before(com.ksh321.songrecord.api.locking.LockOrder.Rank.USER_SYNC,account.principal().userId().toString());
        jdbc.queryForList("SELECT last_change_seq FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(account.principal().userId()));
        var rows=jdbc.query("SELECT id,name,revision,deleted_at,updated_at FROM playlist WHERE user_id=? AND id=? AND deleted_at IS NOT NULL",(rs,n)->wire(rs),bytes(account.principal().userId()),bytes(id));
        if(!rows.isEmpty())return rows.getFirst();
        var proofs=jdbc.query("SELECT revision,purged_at FROM deletion_ledger WHERE user_id=? AND entity_type='PLAYLIST' AND entity_id=? AND object_generation IS NULL",(rs,n)->Map.<String,Object>of("id",id.toString(),"revision",rs.getLong(1),"deleted_at",rs.getTimestamp(2).toLocalDateTime().toInstant(ZoneOffset.UTC).toString()),bytes(account.principal().userId()),bytes(id));
        return proofs.isEmpty()?null:proofs.getFirst();
    }
    private AccountChanges.Batch<IdempotentMutations.Reply> batch(UUID id,int status,Map<String,Object> snapshot){
        String payload=JSON.writeValueAsString(snapshot.get("deleted_at")==null?snapshot:deletion(snapshot));
        return new AccountChanges.Batch<>(new IdempotentMutations.Reply(status,payload),List.of(new AccountChanges.Change(AccountChanges.Entity.PLAYLIST,id,((Number)snapshot.get("revision")).longValue(),snapshot.get("deleted_at")==null?AccountChanges.Operation.UPSERT:AccountChanges.Operation.DELETE,payload)));
    }
    private static Map<String,Object> deletion(Map<String,Object> value){return Map.of("id",value.get("id"),"status","DELETED","revision",value.get("revision"),"deleted_at",value.get("deleted_at"));}
    private Map<String,Object> snapshot(UUID owner,UUID id){return jdbc.queryForObject("SELECT id,name,revision,deleted_at,updated_at FROM playlist WHERE user_id=? AND id=?",(rs,n)->wire(rs),bytes(owner),bytes(id));}
    public KeysetPages.Page<Map<String,Object>> list(String auth,String device,MultiValueMap<String,String> params){
        var account=access.authenticate(auth,device);
        for(var e:params.entrySet())if(!Set.of("state","limit","cursor").contains(e.getKey()) || e.getValue().size()!=1)throw invalid();
        String state=params.getFirst("state");if(state==null)state="ACTIVE";if(!state.equals("ACTIVE"))throw invalid();
        int limit=50;try{if(params.containsKey("limit")){String s=params.getFirst("limit");if(s==null || !s.matches("[1-9][0-9]{0,2}"))throw invalid();limit=PageCursor.pageSize(Integer.parseInt(s));}}catch(NumberFormatException e){throw invalid();}
        var query=new PageCursor.Query("playlists","ID","SR-PLAYLIST-ID-1",JSON.writeValueAsString(Map.of("state",state)),limit);
        return pages.query(account,query,params.getFirst("cursor"),new Source(state));
    }
    private record Source(String state) implements KeysetPages.Source<Map<String,Object>>{
        private String where(){return "user_id=? AND deleted_at IS NULL";}
        public long count(JdbcTemplate db,UUID owner){return db.queryForObject("SELECT COUNT(*) FROM playlist WHERE "+where(),Long.class,bytes(owner));}
        public List<KeysetPages.Entry<Map<String,Object>>> fetch(JdbcTemplate db,UUID owner,PageCursor.Tuple after,int maximum){
            String predicate=where();var args=new ArrayList<Object>();args.add(bytes(owner));
            if(after!=null){predicate+=" AND id>?";args.add(bytes(after.id()));}
            args.add(maximum);
            return db.query("SELECT id,name,revision,deleted_at,updated_at FROM playlist WHERE "+predicate+" ORDER BY id LIMIT ?",(rs,n)->{
                var item=wire(rs);return new KeysetPages.Entry<>(item,new PageCursor.Tuple(List.of(),UUID.fromString((String)item.get("id"))));
            },args.toArray());
        }
        public Comparator<PageCursor.Tuple> order(){return Comparator.comparing(p->p.id().toString());}
    }
    private static Map<String,Object> wire(ResultSet rs)throws SQLException{
        var result=new LinkedHashMap<String,Object>();var b=java.nio.ByteBuffer.wrap(rs.getBytes("id"));result.put("id",new UUID(b.getLong(),b.getLong()).toString());result.put("name",rs.getString("name"));result.put("revision",rs.getLong("revision"));
        for(String key:List.of("deleted_at","updated_at")){var t=rs.getTimestamp(key);result.put(key,t==null?null:t.toLocalDateTime().toInstant(ZoneOffset.UTC).toString());}return result;
    }
    private static JsonNode parse(String body,Set<String> fields){CanonicalRequest.canonical(body);var root=JSON.readTree(body);if(!root.isObject() || root.size()!=fields.size())throw invalid();for(var e:root.properties())if(!fields.contains(e.getKey()))throw invalid();return root;}
    private static String text(JsonNode node){if(node==null || !node.isTextual())throw invalid();return node.asText();}
    private static String name(JsonNode node){var result=InputContracts.validate(InputContracts.Field.PLAYLIST,text(node));if(!result.valid())throw invalid();return result.normalized();}
    private static long revision(JsonNode node){if(node==null || !node.isIntegralNumber() || !node.canConvertToLong() || node.asLong()<1)throw invalid();return node.asLong();}
    private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);}
    private static UUID uuid(String s,boolean resource){try{var id=UUID.fromString(s);if(!id.toString().equals(s))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){if(resource)throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","목록을 찾을 수 없습니다.",false,Map.of());throw invalid();}}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","목록 입력을 확인해 주세요.",false,Map.of());}
    private static ApiException conflict(String code,String message){return new ApiException(HttpStatus.CONFLICT,code,message,false,Map.of());}
}
