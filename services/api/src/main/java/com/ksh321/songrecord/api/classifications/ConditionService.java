package com.ksh321.songrecord.api.classifications;

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

/** Owned condition definitions; legacy codes stay compatible and historical recording names never change. */
public final class ConditionService {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final CreationGuard guard;private final RevisionChanges revisions;private final AccountChanges changes;
    private final KeysetPages pages;private final Clock clock;
    public ConditionService(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,RevisionChanges revisions,AccountChanges changes,KeysetPages pages,Clock clock){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.guard=guard;this.revisions=revisions;this.changes=changes;this.pages=pages;this.clock=clock;
    }
    public IdempotentMutations.Reply create(String auth,String device,String op,String body){
        var account=access.authenticate(auth,device);var root=parse(body,Set.of("id","name"));UUID id=uuid(text(root.get("id")),false);String name=name(root.get("name"));UUID owner=account.principal().userId();
        try{return mutations.execute(account,op,"POST","/v1/conditions",body,()->{
            var result=guard.create(account,CreationGuard.Resource.CONDITION,id,()->changes.write(account,()->{
                unique(owner,id,name);
                var now=now();jdbc.update("INSERT INTO condition_definition(id,user_id,code,name,normalized_name_key,revision,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?)",bytes(id),bytes(owner),id.toString(),name,key(name),now,now);
                return batch(id,201,snapshot(owner,id));
            }).value());
            if(result.created())return result.value();
            if(result.existing().state().equals("ARCHIVED"))throw conflict("CONDITION_ARCHIVED","보관한 컨디션은 다시 생성할 수 없습니다.");
            return new IdempotentMutations.Reply(200,JSON.writeValueAsString(snapshot(owner,id)));
        });}catch(DuplicateKeyException e){throw conflict("CONDITION_ID_CONFLICT","컨디션 식별자를 확인해 주세요.");}
    }
    public IdempotentMutations.Reply rename(String auth,String device,String op,String id,String body){return edit(auth,device,op,id,body,false);}
    public IdempotentMutations.Reply archive(String auth,String device,String op,String id,String body){return edit(auth,device,op,id,body,true);}
    private IdempotentMutations.Reply edit(String auth,String device,String op,String rawId,String body,boolean archive){
        var account=access.authenticate(auth,device);UUID id=uuid(rawId,true),owner=account.principal().userId();
        var root=parse(body,archive?Set.of("base_revision"):Set.of("base_revision","name"));long revision=revision(root.get("base_revision"));String name=archive?null:name(root.get("name"));
        return mutations.execute(account,op,archive?"POST":"PATCH","/v1/conditions/"+id+(archive?"/archive":""),body,()->changes.write(account,()->{
            var updated=revisions.change(account,RevisionChanges.Resource.CONDITION,id.toString(),revision,current->{
                if(archive){if(current.get("archived_at")==null)jdbc.update("UPDATE condition_definition SET archived_at=? WHERE user_id=? AND id=?",now(),bytes(owner),bytes(id));}
                else{
                    if(current.get("archived_at")!=null)throw conflict("CONDITION_ARCHIVED","보관한 컨디션은 이름을 수정할 수 없습니다.");
                    unique(owner,id,name);jdbc.update("UPDATE condition_definition SET name=?,normalized_name_key=? WHERE user_id=? AND id=?",name,key(name),bytes(owner),bytes(id));
                }
            });
            return batch(id,200,updated);
        }).value());
    }
    private AccountChanges.Batch<IdempotentMutations.Reply> batch(UUID id,int status,Map<String,Object> snapshot){
        String payload=JSON.writeValueAsString(snapshot);
        return new AccountChanges.Batch<>(new IdempotentMutations.Reply(status,payload),List.of(new AccountChanges.Change(AccountChanges.Entity.CONDITION,id,((Number)snapshot.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload)));
    }
    private void unique(UUID owner,UUID id,String name){
        if(!jdbc.queryForList("SELECT id FROM condition_definition WHERE user_id=? AND archived_at IS NULL AND normalized_name_key=? AND id<>?",bytes(owner),key(name),bytes(id)).isEmpty())throw conflict("CONDITION_NAME_IN_USE","이미 사용 중인 컨디션 이름입니다.");
    }
    private Map<String,Object> snapshot(UUID owner,UUID id){return jdbc.queryForObject("SELECT id,code,name,revision,archived_at,updated_at FROM condition_definition WHERE user_id=? AND id=?",(rs,n)->wire(rs),bytes(owner),bytes(id));}
    public KeysetPages.Page<Map<String,Object>> list(String auth,String device,MultiValueMap<String,String> params){
        var account=access.authenticate(auth,device);
        for(var e:params.entrySet())if(!Set.of("state","limit","cursor").contains(e.getKey()) || e.getValue().size()!=1)throw invalid();
        String state=params.getFirst("state");if(state==null)state="ACTIVE";if(!Set.of("ACTIVE","ARCHIVED","ALL").contains(state))throw invalid();
        int limit=50;try{if(params.containsKey("limit")){String s=params.getFirst("limit");if(s==null || !s.matches("[1-9][0-9]{0,2}"))throw invalid();limit=PageCursor.pageSize(Integer.parseInt(s));}}catch(NumberFormatException e){throw invalid();}
        var query=new PageCursor.Query("conditions","NORMALIZED_NAME","SR-CONDITION-NFC-ASCII-1",JSON.writeValueAsString(Map.of("state",state)),limit);
        return pages.query(account,query,params.getFirst("cursor"),new Source(state));
    }
    private record Source(String state) implements KeysetPages.Source<Map<String,Object>>{
        private String where(){return "user_id=?"+switch(state){case "ACTIVE"->" AND archived_at IS NULL";case "ARCHIVED"->" AND archived_at IS NOT NULL";default->"";};}
        public long count(JdbcTemplate db,UUID owner){return db.queryForObject("SELECT COUNT(*) FROM condition_definition WHERE "+where(),Long.class,bytes(owner));}
        public List<KeysetPages.Entry<Map<String,Object>>> fetch(JdbcTemplate db,UUID owner,PageCursor.Tuple after,int maximum){
            String predicate=where();var args=new ArrayList<Object>();args.add(bytes(owner));
            if(after!=null){byte[] key=HexFormat.of().parseHex(after.values().getFirst());predicate+=" AND (normalized_name_key>? OR (normalized_name_key=? AND id>?))";args.add(key);args.add(key);args.add(bytes(after.id()));}
            args.add(maximum);
            return db.query("SELECT id,code,name,revision,archived_at,updated_at,normalized_name_key FROM condition_definition WHERE "+predicate+" ORDER BY normalized_name_key,id LIMIT ?",(rs,n)->{
                var item=wire(rs);return new KeysetPages.Entry<>(item,new PageCursor.Tuple(List.of(HexFormat.of().formatHex(rs.getBytes("normalized_name_key"))),UUID.fromString((String)item.get("id"))));
            },args.toArray());
        }
        public Comparator<PageCursor.Tuple> order(){return Comparator.comparing((PageCursor.Tuple p)->p.values().getFirst()).thenComparing(p->p.id().toString());}
    }
    private static Map<String,Object> wire(ResultSet rs)throws SQLException{
        var result=new LinkedHashMap<String,Object>();var b=java.nio.ByteBuffer.wrap(rs.getBytes("id"));result.put("id",new UUID(b.getLong(),b.getLong()).toString());result.put("code",rs.getString("code"));result.put("name",rs.getString("name"));result.put("revision",rs.getLong("revision"));
        for(String key:List.of("archived_at","updated_at")){var t=rs.getTimestamp(key);result.put(key,t==null?null:t.toLocalDateTime().toInstant(ZoneOffset.UTC).toString());}return result;
    }
    private static JsonNode parse(String body,Set<String> fields){CanonicalRequest.canonical(body);var root=JSON.readTree(body);if(!root.isObject() || root.size()!=fields.size())throw invalid();for(var e:root.properties())if(!fields.contains(e.getKey()))throw invalid();return root;}
    private static String text(JsonNode node){if(node==null || !node.isTextual())throw invalid();return node.asText();}
    private static String name(JsonNode node){var result=InputContracts.validate(InputContracts.Field.CONDITION,text(node));if(!result.valid())throw invalid();return result.normalized();}
    private static byte[] key(String name){return DomainOrdering.normalizeText(name).getBytes(StandardCharsets.UTF_8);}
    private static long revision(JsonNode node){if(node==null || !node.isIntegralNumber() || !node.canConvertToLong() || node.asLong()<1)throw invalid();return node.asLong();}
    private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);}
    private static UUID uuid(String s,boolean resource){try{var id=UUID.fromString(s);if(!id.toString().equals(s))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){if(resource)throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","컨디션을 찾을 수 없습니다.",false,Map.of());throw invalid();}}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","컨디션 입력을 확인해 주세요.",false,Map.of());}
    private static ApiException conflict(String code,String message){return new ApiException(HttpStatus.CONFLICT,code,message,false,Map.of());}
}
