package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.InputContracts;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Owner-scoped, revision-checked patch; only song and derived search keys are written. */
public final class SongEditing {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final RevisionChanges revisions;private final AccountChanges changes;
    public SongEditing(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,RevisionChanges revisions,AccountChanges changes){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.revisions=revisions;this.changes=changes;
    }
    public IdempotentMutations.Reply patch(String auth,String device,String op,String id,String body){
        var account=access.authenticate(auth,device);UUID song=parseId(id);var request=parse(body);UUID owner=account.principal().userId();
        try {
            return mutations.execute(account,op,"PATCH","/v1/songs/"+song,body,()->changes.write(account,()->{
                var updated=revisions.change(account,RevisionChanges.Resource.SONG,song.toString(),request.revision,current->{
                    String state=(String)current.get("lifecycle_state");
                    if(!"ACTIVE".equals(state))throw stateConflict(state);
                    var merged=new LinkedHashMap<>(current);merged.putAll(request.fields);validateKey(merged);
                    if(!request.fields.isEmpty()){
                        String assignments=String.join(",",request.fields.keySet().stream().map(key->key+"=?").toList());
                        var args=new ArrayList<Object>(request.fields.values());args.add(bytes(owner));args.add(bytes(song));
                        jdbc.update("UPDATE song SET "+assignments+" WHERE user_id=? AND id=?",args.toArray());
                    }
                    if(request.fields.containsKey("title") || request.fields.containsKey("artist"))
                        SongQueryKeys.replace(jdbc,owner,song,(String)merged.get("title"),(String)merged.get("artist"));
                });
                String payload=JSON.writeValueAsString(wire(updated));
                return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,payload),List.of(
                        new AccountChanges.Change(AccountChanges.Entity.SONG,song,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload)));
            }).value());
        } catch(ApiException e){
            if(!e.code().equals("REVISION_CONFLICT"))throw e;
            @SuppressWarnings("unchecked") var current=(Map<String,Object>)e.details().get("current");
            throw new ApiException(e.status(),e.code(),e.getMessage(),e.retryable(),Map.of("current_revision",e.details().get("current_revision"),"current",wire(current)));
        }
    }
    private record Patch(long revision,Map<String,Object> fields){@Override public String toString(){return "SongPatch[REDACTED]";}}
    private static Patch parse(String body){
        var root=JSON.readTree(CanonicalRequest.canonical(body));if(!root.isObject())throw invalid();
        var base=root.get("base_revision");if(base==null || !base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();
        var fields=new LinkedHashMap<String,Object>();
        for(var entry:root.properties()){
            String name=entry.getKey();JsonNode value=entry.getValue();
            switch(name){
                case "base_revision" -> {}
                case "title","artist" -> {
                    String text=text(value,false);var result=InputContracts.validate(name.equals("title")?InputContracts.Field.TITLE:InputContracts.Field.ARTIST,text);
                    if(!result.valid())throw invalid();fields.put(name,result.normalized());
                }
                case "note" -> {
                    String text=text(value,true);var result=InputContracts.validate(InputContracts.Field.NOTE,text==null?"":text);
                    if(!result.valid())throw invalid();fields.put(name,result.normalized());
                }
                case "version_code" -> fields.put(name,choice(value,false,Set.of("NORMAL","MR","LIVE")));
                case "tier" -> fields.put("song_tier",choice(value,true,Set.of("S","A","B","C","D")));
                case "representative_key_mode" -> fields.put(name,choice(value,true,Set.of("ORIGINAL","MALE","FEMALE")));
                case "representative_key_shift" -> {
                    if(value.isNull())fields.put(name,null);
                    else {if(!value.isIntegralNumber() || !value.canConvertToInt() || value.asInt() < -12 || value.asInt() > 12)throw invalid();fields.put(name,value.asInt());}
                }
                default -> throw invalid();
            }
        }
        return new Patch(base.asLong(),Collections.unmodifiableMap(fields));
    }
    private static String text(JsonNode node,boolean nullable){if(node.isNull() && nullable)return null;if(!node.isTextual())throw invalid();return node.asText();}
    private static String choice(JsonNode value,boolean nullable,Set<String> choices){String text=text(value,nullable);if(text!=null && !choices.contains(text))throw invalid();return text;}
    private static void validateKey(Map<String,Object> merged){
        Object mode=merged.get("representative_key_mode"),shift=merged.get("representative_key_shift");
        if(mode==null && shift==null)return;
        if(mode==null || !(shift instanceof Number number) || number.intValue() < -12 || number.intValue() > 12
                || !Set.of("ORIGINAL","MALE","FEMALE").contains(mode) || (mode.equals("ORIGINAL") && number.intValue()!=0))throw invalid();
    }
    static Map<String,Object> wire(Map<String,Object> snapshot){
        var result=new LinkedHashMap<String,Object>();
        for(String key:List.of("id","revision","updated_at","source_type","tj_number","title","artist","version_code","note","lifecycle_state","representative_key_mode","representative_key_shift","representative_recording_id"))result.put(key,snapshot.get(key));
        result.put("tier",snapshot.get("song_tier"));return result;
    }
    static UUID parseId(String text){try{var id=UUID.fromString(text);if(!id.toString().equals(text))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청한 자료를 찾을 수 없습니다.",false,Map.of());}}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","곡 수정 값을 확인해 주세요.",false,Map.of());}
    static ApiException stateConflict(String state){String code=switch(state){case "TRASHED"->"SONG_RESTORE_REQUIRED";case "PURGE_PENDING"->"SONG_PURGE_PENDING";case "PURGED"->"RESOURCE_PURGED";default->throw new IllegalStateException("Unknown song lifecycle");};return new ApiException(HttpStatus.CONFLICT,code,"기존 곡의 상태를 확인해 주세요.",false,Map.of());}
}
