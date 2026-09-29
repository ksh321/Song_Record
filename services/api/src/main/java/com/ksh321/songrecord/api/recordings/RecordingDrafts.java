package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.InputContracts;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.revision.CreationGuard;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Metadata-only DRAFT creation. No storage quota, upload or external provider calls. */
public final class RecordingDrafts {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final CreationGuard guard;private final AccountChanges changes;private final Clock clock;
    public RecordingDrafts(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,CreationGuard guard,AccountChanges changes,Clock clock){this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.guard=guard;this.changes=changes;this.clock=clock;}
    public IdempotentMutations.Reply create(String auth,String device,String op,String body){
        var account=access.authenticate(auth,device);var request=parse(body);var principal=account.principal();UUID owner=principal.userId();
        try{return mutations.execute(account,op,"POST","/v1/recordings",body,()->{
            var result=guard.create(account,CreationGuard.Resource.RECORDING,request.id,()->{
                // Guard holds USER_SYNC through commit. Song lifecycle writers share that lock.
                // Do not acquire a SONG lock after the guard's RECORDING lock.
                if(request.song!=null){
                    var rows=jdbc.queryForList("SELECT lifecycle_state FROM song WHERE user_id=? AND id=?",String.class,bytes(owner),bytes(request.song));
                    if(rows.isEmpty())throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","연결할 곡을 찾을 수 없습니다.");
                    if(!rows.getFirst().equals("ACTIVE"))throw error(HttpStatus.CONFLICT,"SONG_NOT_ACTIVE","활성 곡에만 연결할 수 있습니다.");
                }
                return changes.write(account,()->{
                    var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);
                    jdbc.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,note,condition_code,condition_name_snapshot,recorded_at,timezone_id,timezone_offset_minutes,metadata_state,lifecycle_state,revision,link_revision,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'DRAFT','ACTIVE',1,1,?,?)",
                        bytes(request.id),bytes(owner),bytes(principal.deviceId()),request.song==null?null:bytes(request.song),request.title,request.artist,request.version,request.keyMode,request.keyShift,request.note,request.condition,request.condition==null?null:com.ksh321.songrecord.api.classifications.ConditionCatalog.name(request.condition),LocalDateTime.ofInstant(request.time,ZoneOffset.UTC),request.zone,request.offset,now,now);
                    RecordingQueryKeys.insert(jdbc,owner,request.id,request.title);
                    String payload=JSON.writeValueAsString(snapshot(owner,request.id));
                    return new AccountChanges.Batch<>(new IdempotentMutations.Reply(201,payload),List.of(new AccountChanges.Change(AccountChanges.Entity.RECORDING,request.id,1,AccountChanges.Operation.UPSERT,payload)));
                }).value();
            });
            if(result.created())return result.value();
            String state=result.existing().state();
            if(!state.equals("ACTIVE"))throw error(HttpStatus.CONFLICT,switch(state){case "PURGED"->"RESOURCE_PURGED";case "TRASHED"->"RECORDING_RESTORE_REQUIRED";default->"RECORDING_PURGE_PENDING";},"기존 녹음 상태를 확인해 주세요.");
            var current=snapshot(owner,request.id);
            if(!current.get("metadata_state").equals("DRAFT"))throw error(HttpStatus.CONFLICT,"RECORDING_ALREADY_SAVED","이미 저장 완료된 녹음입니다.");
            return new IdempotentMutations.Reply(200,JSON.writeValueAsString(current));
        });}catch(DuplicateKeyException e){throw error(HttpStatus.CONFLICT,"RECORDING_ID_CONFLICT","녹음 식별자를 확인해 주세요.");}
    }
    Map<String,Object> snapshot(UUID owner,UUID id){
        return jdbc.queryForObject("SELECT * FROM recording WHERE user_id=? AND id=?",(rs,n)->{
            var m=new LinkedHashMap<String,Object>();m.put("id",id.toString());m.put("origin_device_id",uuid(rs.getBytes("origin_device_id")));m.put("song_id",uuid(rs.getBytes("song_id")));
            m.put("revision",rs.getLong("revision"));m.put("link_revision",rs.getLong("link_revision"));
            for(String field:List.of("title_snapshot","artist_snapshot","version_code","key_mode","note","metadata_state","lifecycle_state","timezone_id","condition_code","condition_name_snapshot"))m.put(field,rs.getString(field));
            m.put("key_shift",rs.getObject("key_shift"));m.put("timezone_offset_minutes",rs.getInt("timezone_offset_minutes"));
            for(String field:List.of("recorded_at","updated_at"))m.put(field,rs.getTimestamp(field).toLocalDateTime().toInstant(ZoneOffset.UTC).toString());
            return m;
        },bytes(owner),bytes(id));
    }
    private record Draft(UUID id,UUID song,String title,String artist,String version,String keyMode,Integer keyShift,String note,String condition,Instant time,String zone,int offset){@Override public String toString(){return "RecordingDraft[REDACTED]";}}
    private static Draft parse(String body){
        CanonicalRequest.canonical(body); // Validate duplicate keys/trailing tokens without changing numeric node types.
        var root=JSON.readTree(body);if(!root.isObject())throw invalid();
        var allowed=Set.of("id","metadata_state","song_id","title_snapshot","artist_snapshot","version_code","key_mode","key_shift","note","condition_code","recorded_at","timezone_id","timezone_offset_minutes");
        for(var entry:root.properties())if(!allowed.contains(entry.getKey()))throw invalid();
        if(!"DRAFT".equals(text(root,"metadata_state",false)))throw invalid();
        UUID id=parseUuid(text(root,"id",false));String song=text(root,"song_id",true);
        String title=name(root,"title_snapshot",InputContracts.Field.TITLE),artist=name(root,"artist_snapshot",InputContracts.Field.ARTIST);
        String version=root.has("version_code")?text(root,"version_code",false):"NORMAL";if(!Set.of("NORMAL","MR","LIVE").contains(version))throw invalid();
        String mode=text(root,"key_mode",true);var shift=root.get("key_shift");Integer key=null;
        if(shift!=null && !shift.isNull()){if(!shift.isIntegralNumber() || !shift.canConvertToInt() || shift.asInt() < -12 || shift.asInt()>12)throw invalid();key=shift.asInt();}
        if((mode==null)!=(key==null) || mode!=null && (!Set.of("ORIGINAL","MALE","FEMALE").contains(mode) || mode.equals("ORIGINAL") && key!=0))throw invalid();
        String rawNote=text(root,"note",true);var note=InputContracts.validate(InputContracts.Field.NOTE,rawNote==null?"":rawNote);if(!note.valid())throw invalid();
        String time=text(root,"recorded_at",false),zone=text(root,"timezone_id",false);Instant instant;
        if(!time.matches("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?Z") || zone.length()>64 || !ZoneId.getAvailableZoneIds().contains(zone))throw invalid();
        try{instant=OffsetDateTime.parse(time).toInstant();int year=instant.atOffset(ZoneOffset.UTC).getYear();if(year<1000 || year>9999)throw invalid();}catch(DateTimeException e){throw invalid();}
        var offset=root.get("timezone_offset_minutes");if(offset==null || !offset.isIntegralNumber() || !offset.canConvertToInt() || offset.asInt() < -1080 || offset.asInt()>1080)throw invalid();
        String condition=text(root,"condition_code",true);
        if(condition!=null && !com.ksh321.songrecord.api.classifications.ConditionCatalog.contains(condition))throw invalid();
        return new Draft(id,song==null?null:parseUuid(song),title,artist,version,mode,key,note.normalized(),condition,instant,zone,offset.asInt());
    }
    private static String name(JsonNode root,String field,InputContracts.Field contract){String text=text(root,field,true);if(text==null)return null;var result=InputContracts.validate(contract,text);if(result.normalized().isEmpty())return null;if(!result.valid())throw invalid();return result.normalized();}
    private static String text(JsonNode root,String field,boolean nullable){var node=root.get(field);if(node==null || node.isNull()){if(nullable)return null;throw invalid();}if(!node.isTextual())throw invalid();return node.asText();}
    private static UUID parseUuid(String text){try{UUID id=UUID.fromString(text);if(!id.toString().equals(text))throw invalid();return id;}catch(IllegalArgumentException e){throw invalid();}}
    private static String uuid(byte[] data){if(data==null)return null;var b=java.nio.ByteBuffer.wrap(data);return new UUID(b.getLong(),b.getLong()).toString();}
    private static ApiException invalid(){return error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","녹음 초안 입력을 확인해 주세요.");}
    private static ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message,false,Map.of());}
}
