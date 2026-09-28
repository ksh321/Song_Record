package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.InputContracts;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.revision.CreationGuard;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

public final class SongCreation {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final CreationGuard guard;private final AccountChanges changes;private final TjCandidates candidates;private final Clock clock;
    public SongCreation(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,AccountChanges changes,TjCandidates candidates,Clock clock){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.guard=guard;this.changes=changes;this.candidates=candidates;this.clock=clock;
    }
    public IdempotentMutations.Reply create(String auth,String device,String op,String body){
        var account=access.authenticate(auth,device);var request=parse(body);UUID owner=account.principal().userId();
        try{return mutations.execute(account,op,"POST","/v1/songs",body,()->{
            // Source-token verification here is local only. Network refresh belongs outside this transaction.
            var proof=request.type.equals("TJ")?candidates.require(request.proof,TjCandidates.Purpose.SONG):null;
            var result=guard.create(account,CreationGuard.Resource.SONG,request.id,()->{
                // Account sync lock held by guard serializes all participating song writers.
                var duplicates=proof==null?List.<UUID>of():jdbc.query("SELECT id FROM song WHERE user_id=? AND reserved_tj_number=?",(rs,n)->uuid(rs.getBytes(1)),bytes(owner),proof.number());
                if(!duplicates.isEmpty())return existing(owner,duplicates.getFirst(),request.type,proof.number());
                return changes.write(account,()->{
                    String title=normalized(InputContracts.Field.TITLE,request.title==null?proof.title():request.title);
                    String artist=normalized(InputContracts.Field.ARTIST,request.artist==null?proof.artist():request.artist);
                    var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);
                    jdbc.update("INSERT INTO song(id,user_id,source_type,tj_number,title,artist,version_code,note,song_tier,lifecycle_state,revision,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,'ACTIVE',1,?,?)",
                            bytes(request.id),bytes(owner),request.type,proof==null?null:proof.number(),title,artist,request.version,request.note,request.tier,now,now);
                    SongQueryKeys.insert(jdbc,owner,request.id,title,artist);
                    if(proof!=null){
                        String ref=proof.provider()+":"+proof.number();if(ref.length()>255)throw new IllegalStateException("Invalid candidate source reference");
                        jdbc.update("INSERT INTO song_source(song_id,user_id,provider,source_title,source_artist,source_ref,verified_at,created_at) VALUES(?,?,'TJ',?,?,?,?,?)",
                                bytes(request.id),bytes(owner),proof.title(),proof.artist(),ref,now,now);
                    }
                    var song=snapshot(owner,request.id);var reply=reply(201,true,song);
                    return new AccountChanges.Batch<>(reply,List.of(new AccountChanges.Change(AccountChanges.Entity.SONG,request.id,1,AccountChanges.Operation.UPSERT,JSON.writeValueAsString(song))));
                }).value();
            });
            return result.created()?result.value():existing(owner,request.id,request.type,proof==null?null:proof.number());
        });}catch(DuplicateKeyException e){throw new ApiException(HttpStatus.CONFLICT,"SONG_ID_CONFLICT","곡 식별자를 확인해 주세요.",false,Map.of());}
    }
    private IdempotentMutations.Reply existing(UUID owner,UUID id,String type,String number){
        var song=snapshot(owner,id);String state=(String)song.get("lifecycle_state");
        if("PURGED".equals(state))throw conflict("RESOURCE_PURGED");
        if(!type.equals(song.get("source_type")) || !Objects.equals(number,song.get("tj_number")))throw conflict("SONG_ID_CONFLICT");
        if("TRASHED".equals(state))throw conflict("SONG_RESTORE_REQUIRED");
        if("PURGE_PENDING".equals(state))throw conflict("SONG_PURGE_PENDING");
        if(!"ACTIVE".equals(state))throw new IllegalStateException("Invalid song lifecycle");
        return reply(200,false,song);
    }
    private Map<String,Object> snapshot(UUID owner,UUID id){
        var rows=jdbc.query("SELECT id,revision,updated_at,source_type,tj_number,title,artist,version_code,song_tier,note,lifecycle_state FROM song WHERE user_id=? AND id=?",(rs,n)->{
            var m=new LinkedHashMap<String,Object>();m.put("id",uuid(rs.getBytes("id")).toString());m.put("revision",rs.getLong("revision"));
            m.put("updated_at",rs.getTimestamp("updated_at").toLocalDateTime().toInstant(ZoneOffset.UTC).toString());
            for(String name:List.of("source_type","tj_number","title","artist","version_code","note","lifecycle_state"))m.put(name,rs.getString(name));
            m.put("tier",rs.getString("song_tier"));return m;
        },bytes(owner),bytes(id));
        if(rows.size()!=1)throw new IllegalStateException("Song disappeared inside account transaction");return rows.getFirst();
    }
    private static IdempotentMutations.Reply reply(int status,boolean created,Map<String,Object> song){return new IdempotentMutations.Reply(status,JSON.writeValueAsString(Map.of("created",created,"canonical_song_id",song.get("id"),"song",song)));}
    private record Request(UUID id,String type,String proof,String title,String artist,String version,String note,String tier){@Override public String toString(){return "SongRequest[REDACTED]";}}
    private static Request parse(String body){
        var root=JSON.readTree(CanonicalRequest.canonical(body));if(!root.isObject())throw invalid();
        var allowed=Set.of("id","source_type","source_token","manual_reason","title","artist","version_code","note","tier");
        for(var entry:root.properties())if(!allowed.contains(entry.getKey()))throw invalid();
        String id=text(root,"id",true),type=text(root,"source_type",true);
        if(!Set.of("TJ","MANUAL").contains(type))throw invalid();
        boolean manual=type.equals("MANUAL");
        if(manual){
            if(root.has("source_token") || !"TJ_NOT_FOUND".equals(text(root,"manual_reason",true)))throw invalid();
        }else if(root.has("manual_reason"))throw invalid();
        String proof=manual?null:text(root,"source_token",true);
        UUID uuid;try{uuid=UUID.fromString(id);if(!uuid.toString().equals(id))throw invalid();}catch(IllegalArgumentException e){throw invalid();}
        String title=text(root,"title",manual),artist=text(root,"artist",manual),version=text(root,"version_code",false),note=text(root,"note",false),tier=text(root,"tier",false);
        if(version==null)version="NORMAL";if(!Set.of("NORMAL","MR","LIVE").contains(version))throw invalid();
        if(tier!=null && !Set.of("S","A","B","C","D").contains(tier))throw invalid();
        if(title!=null)title=normalized(InputContracts.Field.TITLE,title);if(artist!=null)artist=normalized(InputContracts.Field.ARTIST,artist);
        note=normalized(InputContracts.Field.NOTE,note==null?"":note);
        return new Request(uuid,type,proof,title,artist,version,note,tier);
    }
    private static String text(JsonNode root,String key,boolean required){var value=root.get(key);if(value==null){if(required)throw invalid();return null;}if(value.isNull() && (key.equals("tier") || key.equals("note")))return null;if(!value.isTextual())throw invalid();return value.asText();}
    private static String normalized(InputContracts.Field field,String value){var result=InputContracts.validate(field,value);if(!result.valid())throw invalid();return result.normalized();}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","곡 등록 값을 확인해 주세요.",false,Map.of());}
    private static ApiException conflict(String code){return new ApiException(HttpStatus.CONFLICT,code,"기존 곡의 상태를 확인해 주세요.",false,Map.of());}
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] data){var b=ByteBuffer.wrap(data);return new UUID(b.getLong(),b.getLong());}
}
