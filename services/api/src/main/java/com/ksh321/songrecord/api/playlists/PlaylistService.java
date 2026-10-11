package com.ksh321.songrecord.api.playlists;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.*;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.revision.*;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.songs.TjCandidates;
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
    private final TjCandidates candidates;
    public PlaylistService(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,RevisionChanges revisions,AccountChanges changes,KeysetPages pages,Clock clock,com.ksh321.songrecord.api.jobs.JobQueue jobs,TjCandidates candidates){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.guard=guard;this.revisions=revisions;this.changes=changes;this.pages=pages;this.clock=clock;this.jobs=jobs;
        this.candidates=candidates;
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
    public Map<String,Object> items(String auth,String device,String rawId){
        var account=access.authenticate(auth,device);var owner=account.principal().userId();var id=uuid(rawId,true);
        var parent=activeParent(owner,id);var result=aggregate(owner,id,parent);
        if(!Objects.equals(activeParent(owner,id).get("revision"),parent.get("revision")))throw conflict("REVISION_CONFLICT","최신 목록을 다시 확인해 주세요.");
        access.revalidate(account);return result;
    }
    public IdempotentMutations.Reply addItem(String auth,String device,String op,String rawId,String body){
        var account=access.authenticate(auth,device);var owner=account.principal().userId();var id=uuid(rawId,true);
        var decoded=JSON.readTree(CanonicalRequest.canonical(body));boolean candidate=decoded.has("source_token");
        if(decoded.has("song_ids"))return addMany(account,op,id,body);
        var root=parse(body,candidate?Set.of("source_token","base_revision"):Set.of("song_id","base_revision"));
        UUID songId=candidate?null:uuid(text(root.get("song_id")),true);long base=revision(root.get("base_revision"));
        String sourceToken=candidate?text(root.get("source_token")):null;
        return mutations.executePrepared(account,op,"POST","/v1/playlists/"+id+"/items",body,
            ()->candidate?candidates.prepare(sourceToken,TjCandidates.Purpose.PLAYLIST,owner):null,prepared->{
            var proof=prepared==null?null:candidates.requirePrepared(prepared,TjCandidates.Purpose.PLAYLIST);
            if(revisionsReadDeleted(account,id)!=null)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");
            var parent=activeParent(owner,id);requireRevision(parent,base);
            final String key;
            if(songId==null){key="tj:"+proof.number();}
            else {
                var songs=jdbc.queryForList("SELECT source_type,tj_number,lifecycle_state FROM song WHERE user_id=? AND id=?",bytes(owner),bytes(songId));
                if(songs.isEmpty())throw notFound();var song=songs.getFirst();
                if(!"ACTIVE".equals(song.get("lifecycle_state")))throw conflict("SONG_NOT_ACTIVE","활성 내 곡만 추가할 수 있습니다.");
                key=switch((String)song.get("source_type")){case "TJ"->"tj:"+song.get("tj_number");case "MANUAL"->"manual:"+songId;default->throw invalid();};
            }
            var existing=jdbc.query("SELECT id FROM playlist_item WHERE user_id=? AND playlist_id=? AND entry_key=?",(rs,n)->asUuid(rs.getBytes(1)),bytes(owner),bytes(id),key);
            if(!existing.isEmpty())return additionReply(owner,id,parent,existing.getFirst(),false,200);
            return changes.write(account,()->{
                if(songId!=null)revisions.lock(account,RevisionChanges.Resource.SONG,songId.toString());
                UUID item=UUID.randomUUID();
                var updated=revisions.change(account,RevisionChanges.Resource.PLAYLIST,id.toString(),base,current->{
                    if(current.get("deleted_at")!=null)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");
                    Long max=jdbc.queryForObject("SELECT MAX(position) FROM playlist_item WHERE user_id=? AND playlist_id=?",Long.class,bytes(owner),bytes(id));
                    if(max!=null && max==Long.MAX_VALUE)throw conflict("PLAYLIST_POSITION_LIMIT","목록 순서를 확인해 주세요.");
                    var time=now();String snapshot=proof==null?null:JSON.writeValueAsString(Map.of("provider",proof.provider(),"brand","TJ","number",proof.number(),"title",proof.title(),"artist",proof.artist(),"verified_at",clock.instant().toString()));
                    jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,candidate_brand,candidate_number,candidate_snapshot,entry_key,position,hidden_by_batch_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,NULL,?,?)",bytes(item),bytes(owner),bytes(id),songId==null?null:bytes(songId),proof==null?null:"TJ",proof==null?null:proof.number(),snapshot,key,max==null?0:max+1,time,time);
                });
                var full=aggregate(owner,id,updated);String change=JSON.writeValueAsString(full);
                return new AccountChanges.Batch<>(additionReply(full,item,true,201),List.of(new AccountChanges.Change(AccountChanges.Entity.PLAYLIST_ITEM,item,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,change)));
            }).value();
        });
    }
    /** One immutable mutation and one parent revision for a multi-selection. */
    private IdempotentMutations.Reply addMany(AccountAccess.Account account,String op,UUID id,String body){
        UUID owner=account.principal().userId();var root=parse(body,Set.of("song_ids","base_revision"));
        var values=root.get("song_ids");if(values==null || !values.isArray() || values.isEmpty() || values.size()>100)throw invalid();
        var selected=new ArrayList<UUID>();for(var value:values){UUID song=uuid(text(value),true);if(selected.contains(song))throw invalid();selected.add(song);}
        long base=revision(root.get("base_revision"));
        return mutations.execute(account,op,"POST","/v1/playlists/"+id+"/items",body,()->{
            if(revisionsReadDeleted(account,id)!=null)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");
            var parent=activeParent(owner,id);requireRevision(parent,base);
                for(UUID song:selected.stream().sorted(Comparator.comparing(UUID::toString)).toList())revisions.lock(account,RevisionChanges.Resource.SONG,song.toString());
                var ids=new ArrayList<UUID>();var additions=new LinkedHashMap<UUID,UUID>();var keys=new HashMap<UUID,String>();
                for(UUID song:selected){
                    var rows=jdbc.queryForList("SELECT source_type,tj_number,lifecycle_state FROM song WHERE user_id=? AND id=?",bytes(owner),bytes(song));
                    if(rows.isEmpty())throw notFound();var row=rows.getFirst();
                    if(!"ACTIVE".equals(row.get("lifecycle_state")))throw conflict("SONG_NOT_ACTIVE","활성 내 곡만 추가할 수 있습니다.");
                    String key=switch((String)row.get("source_type")){case "TJ"->"tj:"+row.get("tj_number");case "MANUAL"->"manual:"+song;default->throw invalid();};keys.put(song,key);
                    var existing=jdbc.queryForList("SELECT id,hidden_by_batch_id FROM playlist_item WHERE user_id=? AND playlist_id=? AND entry_key=?",bytes(owner),bytes(id),key);
                    if(existing.isEmpty()){UUID item=UUID.randomUUID();ids.add(item);additions.put(item,song);}
                    else {if(existing.getFirst().get("hidden_by_batch_id")!=null)throw conflict("PLAYLIST_ITEM_HIDDEN","숨겨진 항목 상태를 확인해 주세요.");ids.add(asUuid((byte[])existing.getFirst().get("id")));}
                }
                if(additions.isEmpty())return multiReply(aggregate(owner,id,parent),ids,false);
            return changes.write(account,()->{
                Map<String,Object> updated=parent;
                if(!additions.isEmpty())updated=revisions.change(account,RevisionChanges.Resource.PLAYLIST,id.toString(),base,current->{
                    Long max=jdbc.queryForObject("SELECT MAX(position) FROM playlist_item WHERE user_id=? AND playlist_id=?",Long.class,bytes(owner),bytes(id));
                    long position=max==null?-1:max;if(position>Long.MAX_VALUE-additions.size())throw conflict("PLAYLIST_POSITION_LIMIT","목록 순서를 확인해 주세요.");
                    for(var entry:additions.entrySet()){
                        var time=now();jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,entry_key,position,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",bytes(entry.getKey()),bytes(owner),bytes(id),bytes(entry.getValue()),keys.get(entry.getValue()),++position,time,time);
                    }
                });
                var full=aggregate(owner,id,updated);
                var events=new ArrayList<AccountChanges.Change>();for(UUID item:additions.keySet())events.add(new AccountChanges.Change(AccountChanges.Entity.PLAYLIST_ITEM,item,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,JSON.writeValueAsString(full)));
                return new AccountChanges.Batch<>(multiReply(full,ids,true),events);
            }).value();
        });
    }
    private static IdempotentMutations.Reply multiReply(Map<String,Object> full,List<UUID> ids,boolean created){var wire=new LinkedHashMap<>(full);wire.put("item_ids",ids.stream().map(UUID::toString).toList());wire.put("created",created);return new IdempotentMutations.Reply(created?201:200,JSON.writeValueAsString(wire));}
    private Map<String,Object> activeParent(UUID owner,UUID id){
        var rows=jdbc.query("SELECT id,name,revision,deleted_at,updated_at FROM playlist WHERE user_id=? AND id=?",(rs,n)->wire(rs),bytes(owner),bytes(id));
        if(rows.isEmpty())throw notFound();var parent=rows.getFirst();if(parent.get("deleted_at")!=null)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");return parent;
    }
    private static void requireRevision(Map<String,Object> parent,long base){if(((Number)parent.get("revision")).longValue()!=base)throw new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT","최신 목록을 확인해 주세요.",false,Map.of("current_revision",parent.get("revision"),"current",parent));}
    private Map<String,Object> aggregate(UUID owner,UUID id,Map<String,Object> header){return aggregate(jdbc,owner,id,header);}
    private static Map<String,Object> aggregate(JdbcTemplate jdbc,UUID owner,UUID id,Map<String,Object> header){
        var parent=new LinkedHashMap<>(header);parent.put("created_at",jdbc.queryForObject("SELECT created_at FROM playlist WHERE user_id=? AND id=?",Timestamp.class,bytes(owner),bytes(id)).toLocalDateTime().toInstant(ZoneOffset.UTC).toString());
        var items=jdbc.query("SELECT i.* FROM playlist_item i LEFT JOIN song s ON s.user_id=i.user_id AND s.id=i.song_id WHERE i.user_id=? AND i.playlist_id=? AND i.hidden_by_batch_id IS NULL AND (i.song_id IS NULL OR s.lifecycle_state='ACTIVE') ORDER BY i.position,i.id",(rs,n)->{
            var value=new LinkedHashMap<String,Object>();
            for(String field:List.of("id","user_id","playlist_id","song_id","hidden_by_batch_id")){var b=rs.getBytes(field);value.put(field,b==null?null:asUuid(b).toString());}
            for(String field:List.of("candidate_brand","candidate_number","entry_key"))value.put(field,rs.getString(field));
            var candidate=rs.getString("candidate_snapshot");value.put("candidate_snapshot",candidate==null?null:JSON.readValue(candidate,Map.class));value.put("position",rs.getLong("position"));
            for(String field:List.of("created_at","updated_at"))value.put(field,rs.getTimestamp(field).toLocalDateTime().toInstant(ZoneOffset.UTC).toString());return value;
        },bytes(owner),bytes(id));return Map.of("playlist",parent,"items",items);
    }
    /** Caller owns the new Song transaction and account sync lock. Parents lock in ID order. */
    public static List<AccountChanges.Change> linkNewSong(JdbcTemplate jdbc,RevisionChanges revisions,AccountAccess.Account account,UUID songId,String number,Clock clock){
        UUID owner=account.principal().userId();
        var parents=jdbc.query("SELECT DISTINCT p.id FROM playlist p JOIN playlist_item i ON i.user_id=p.user_id AND i.playlist_id=p.id WHERE p.user_id=? AND p.deleted_at IS NULL AND i.song_id IS NULL AND i.candidate_brand='TJ' AND i.candidate_number=? AND i.hidden_by_batch_id IS NULL ORDER BY p.id",(rs,n)->asUuid(rs.getBytes(1)),bytes(owner),number);
        var result=new ArrayList<AccountChanges.Change>();
        for(UUID id:parents){
            var current=revisions.lock(account,RevisionChanges.Resource.PLAYLIST,id.toString());
            long base=((Number)current.get("revision")).longValue();
            var itemIds=jdbc.query("SELECT id FROM playlist_item WHERE user_id=? AND playlist_id=? AND song_id IS NULL AND candidate_brand='TJ' AND candidate_number=? AND hidden_by_batch_id IS NULL ORDER BY id",(rs,n)->asUuid(rs.getBytes(1)),bytes(owner),bytes(id),number);
            var updated=revisions.change(account,RevisionChanges.Resource.PLAYLIST,id.toString(),base,old->{
                jdbc.update("UPDATE playlist_item SET song_id=?,updated_at=? WHERE user_id=? AND playlist_id=? AND song_id IS NULL AND candidate_brand='TJ' AND candidate_number=? AND hidden_by_batch_id IS NULL",bytes(songId),LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS),bytes(owner),bytes(id),number);
            });
            // Each entry carries the same complete parent aggregate; position and IDs stay unchanged.
            String payload=JSON.writeValueAsString(aggregate(jdbc,owner,id,updated));
            for(UUID item:itemIds)result.add(new AccountChanges.Change(AccountChanges.Entity.PLAYLIST_ITEM,item,base+1,AccountChanges.Operation.UPSERT,payload));
        }
        return result;
    }
    public IdempotentMutations.Reply linkSong(String auth,String device,String op,String rawId,String rawItem,String body){
        var account=access.authenticate(auth,device);UUID owner=account.principal().userId(),id=uuid(rawId,true),itemId=uuid(rawItem,true);
        var root=parse(body,Set.of("song_id","base_revision"));UUID songId=uuid(text(root.get("song_id")),true);long base=revision(root.get("base_revision"));
        return mutations.execute(account,op,"PATCH","/v1/playlists/"+id+"/items/"+itemId+"/song",body,()->{
            if(revisionsReadDeleted(account,id)!=null)throw conflict("PLAYLIST_DELETED","영구 삭제된 목록입니다.");
            var parent=activeParent(owner,id);requireRevision(parent,base);
            var songs=jdbc.queryForList("SELECT source_type,tj_number,lifecycle_state FROM song WHERE user_id=? AND id=?",bytes(owner),bytes(songId));
            if(songs.isEmpty())throw notFound();var song=songs.getFirst();
            if(!"ACTIVE".equals(song.get("lifecycle_state")))throw conflict("SONG_NOT_ACTIVE","활성 내 곡만 연결할 수 있습니다.");
            var items=jdbc.queryForList("SELECT song_id,candidate_brand,candidate_number,hidden_by_batch_id FROM playlist_item WHERE user_id=? AND playlist_id=? AND id=?",bytes(owner),bytes(id),bytes(itemId));
            if(items.isEmpty())throw notFound();var item=items.getFirst();
            if(!"TJ".equals(song.get("source_type")) || !"TJ".equals(item.get("candidate_brand")) || !Objects.equals(song.get("tj_number"),item.get("candidate_number")) || item.get("hidden_by_batch_id")!=null)throw invalid();
            if(item.get("song_id")!=null){if(!songId.equals(asUuid((byte[])item.get("song_id"))))throw invalid();return linkReply(aggregate(owner,id,parent),itemId,false);}
            return changes.write(account,()->{
                revisions.lock(account,RevisionChanges.Resource.SONG,songId.toString());
                var updated=revisions.change(account,RevisionChanges.Resource.PLAYLIST,id.toString(),base,old->jdbc.update("UPDATE playlist_item SET song_id=?,updated_at=? WHERE user_id=? AND playlist_id=? AND id=? AND song_id IS NULL",bytes(songId),now(),bytes(owner),bytes(id),bytes(itemId)));
                var full=aggregate(owner,id,updated);
                return new AccountChanges.Batch<>(linkReply(full,itemId,true),List.of(new AccountChanges.Change(AccountChanges.Entity.PLAYLIST_ITEM,itemId,base+1,AccountChanges.Operation.UPSERT,JSON.writeValueAsString(full))));
            }).value();
        });
    }
    private static IdempotentMutations.Reply linkReply(Map<String,Object> full,UUID item,boolean changed){var value=new LinkedHashMap<>(full);value.put("item_id",item.toString());value.put("changed",changed);return new IdempotentMutations.Reply(200,JSON.writeValueAsString(value));}
    private IdempotentMutations.Reply additionReply(UUID owner,UUID id,Map<String,Object> parent,UUID item,boolean created,int status){return additionReply(aggregate(owner,id,parent),item,created,status);}
    private static IdempotentMutations.Reply additionReply(Map<String,Object> aggregate,UUID item,boolean created,int status){var result=new LinkedHashMap<>(aggregate);result.put("item_id",item.toString());result.put("created",created);return new IdempotentMutations.Reply(status,JSON.writeValueAsString(result));}
    private static UUID asUuid(byte[] value){var b=java.nio.ByteBuffer.wrap(value);return new UUID(b.getLong(),b.getLong());}
    private static ApiException notFound(){return new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","내 곡 또는 목록을 찾을 수 없습니다.",false,Map.of());}
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
