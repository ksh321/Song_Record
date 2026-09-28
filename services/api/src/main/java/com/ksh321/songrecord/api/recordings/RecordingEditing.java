package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.domain.InputContracts;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Partial metadata edits. Account serialization covers recording, classifications, history and jobs. */
public final class RecordingEditing {
    private static final JsonMapper JSON=new JsonMapper();
    private static final List<String> TIME_FIELDS=List.of("recorded_at","timezone_id","timezone_offset_minutes");
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final RevisionChanges revisions;private final AccountChanges changes;private final RecordingDrafts drafts;
    private final RecordingSaving saving;private final JobQueue jobs;
    public RecordingEditing(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,RevisionChanges revisions,
            AccountChanges changes,RecordingDrafts drafts,RecordingSaving saving,JobQueue jobs){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.revisions=revisions;this.changes=changes;this.drafts=drafts;this.saving=saving;this.jobs=jobs;
    }
    public IdempotentMutations.Reply patch(String auth,String device,String op,String id,String body){
        var account=access.authenticate(auth,device);UUID recording=id(id);UUID owner=account.principal().userId();
        CanonicalRequest.canonical(body);var root=JSON.readTree(body);if(!root.isObject())throw invalid();
        // Completed file specs belong exclusively to the existing one-way DRAFT -> SAVED operation.
        if(root.has("file"))return saving.save(auth,device,op,id,body);
        var request=parse(root);
        return mutations.execute(account,op,"PATCH","/v1/recordings/"+recording,body,()->changes.write(account,()->{
            try {
            var updated=revisions.change(account,RevisionChanges.Resource.RECORDING,id,request.revision,current->{
                if(!"ACTIVE".equals(current.get("lifecycle_state")))throw error(HttpStatus.CONFLICT,"RECORDING_NOT_ACTIVE","활성 녹음만 수정할 수 있습니다.");
                String state=(String)current.get("metadata_state");
                if(request.state!=null && !request.state.equals(state)){
                    if("SAVED".equals(state))throw error(HttpStatus.CONFLICT,"RECORDING_ALREADY_SAVED","저장 완료된 녹음을 초안으로 되돌릴 수 없습니다.");
                    throw invalid(); // SAVED transition requires the immutable completed-file specification.
                }
                var before=drafts.snapshot(owner,recording);var merged=new LinkedHashMap<>(before);merged.putAll(request.fields);
                validateMerged(merged,state);
                var fields=new LinkedHashMap<>(request.fields);
                if(fields.containsKey("condition_code") && !Objects.equals(fields.get("condition_code"),current.get("condition_code"))){
                    Object code=fields.get("condition_code");
                    var definitions=code==null?List.<Map<String,Object>>of():jdbc.queryForList("SELECT name,archived_at FROM condition_definition WHERE user_id=? AND code=?",bytes(owner),code);
                    if(code!=null && definitions.isEmpty())throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","컨디션을 찾을 수 없습니다.");
                    if(code!=null && definitions.getFirst().get("archived_at")!=null)throw error(HttpStatus.CONFLICT,"CONDITION_ARCHIVED","보관한 컨디션은 새로 선택할 수 없습니다.");
                    fields.put("condition_name_snapshot",code==null?null:definitions.getFirst().get("name"));
                }
                if(!fields.isEmpty()){
                    String assignments=String.join(",",fields.keySet().stream().map(k->k+"=?").toList());
                    var args=new ArrayList<Object>();fields.forEach((k,v)->args.add(k.equals("recorded_at")?utc((String)v):v));args.add(bytes(owner));args.add(bytes(recording));
                    jdbc.update("UPDATE recording SET "+assignments+" WHERE user_id=? AND id=?",args.toArray());
                }
                if(fields.containsKey("title_snapshot"))RecordingQueryKeys.replace(jdbc,owner,recording,(String)merged.get("title_snapshot"));
                if(request.tags!=null)replaceTags(owner,recording,request.tags);
                boolean corrected=TIME_FIELDS.stream().anyMatch(k->!Objects.equals(before.get(k),merged.get(k)));
                if(corrected){
                    jdbc.update("INSERT INTO recording_time_correction(user_id,recording_id,revision,actor_device_id,old_recorded_at,new_recorded_at,old_timezone_id,new_timezone_id,old_offset_minutes,new_offset_minutes) VALUES(?,?,?,?,?,?,?,?,?,?)",
                        bytes(owner),bytes(recording),request.revision+1,bytes(account.principal().deviceId()),utc((String)before.get("recorded_at")),utc((String)merged.get("recorded_at")),before.get("timezone_id"),merged.get("timezone_id"),before.get("timezone_offset_minutes"),merged.get("timezone_offset_minutes"));
                }
                if(!Objects.equals(before.get("recorded_at"),merged.get("recorded_at")) && "SAVED".equals(state) && before.get("song_id")!=null){
                    UUID song=UUID.fromString((String)before.get("song_id"));
                    jobs.enqueue(account,JobQueue.Type.POLICY_RECALCULATE,song,UUID.fromString(op),JSON.writeValueAsString(Map.of("song_id",song.toString(),"recording_id",id,"recording_revision",request.revision+1,"reason","RECORDED_AT_CHANGED")));
                }
            });
            String payload=JSON.writeValueAsString(snapshot(owner,recording));
            return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,payload),List.of(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload)));
            } catch(ApiException e){
                if(!e.code().equals("REVISION_CONFLICT"))throw e;
                // Still inside the mutation transaction, with the recording row locked.
                throw new ApiException(e.status(),e.code(),e.getMessage(),e.retryable(),Map.of("current_revision",e.details().get("current_revision"),"current",snapshot(owner,recording)));
            }
        }).value());
    }
    private void replaceTags(UUID owner,UUID recording,List<UUID> tags){
        // All participating tag rename/archive writers must hold the same USER_SYNC lock.
        var existing=jdbc.queryForList("SELECT tag_id FROM recording_tag WHERE user_id=? AND recording_id=?",byte[].class,bytes(owner),bytes(recording));
        var kept=new HashSet<UUID>();for(byte[] b:existing){var v=java.nio.ByteBuffer.wrap(b);kept.add(new UUID(v.getLong(),v.getLong()));}
        for(UUID tag:tags){
            if(kept.contains(tag))continue; // Preserve historical names, including links to archived tags.
            var rows=jdbc.queryForList("SELECT name,archived_at FROM tag WHERE user_id=? AND id=?",bytes(owner),bytes(tag));
            if(rows.isEmpty())throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","태그를 찾을 수 없습니다.");
            if(rows.getFirst().get("archived_at")!=null)throw error(HttpStatus.CONFLICT,"TAG_ARCHIVED","보관한 태그는 새로 선택할 수 없습니다.");
            jdbc.update("INSERT INTO recording_tag(user_id,recording_id,tag_id,name_snapshot) VALUES(?,?,?,?)",bytes(owner),bytes(recording),bytes(tag),rows.getFirst().get("name"));
        }
        for(UUID tag:kept)if(!tags.contains(tag))jdbc.update("DELETE FROM recording_tag WHERE user_id=? AND recording_id=? AND tag_id=?",bytes(owner),bytes(recording),bytes(tag));
    }
    Map<String,Object> snapshot(UUID owner,UUID recording){
        var result=new LinkedHashMap<>(drafts.snapshot(owner,recording));
        jdbc.query("SELECT tier,condition_code,condition_name_snapshot FROM recording WHERE user_id=? AND id=?",rs->{for(String k:List.of("tier","condition_code","condition_name_snapshot"))result.put(k,rs.getString(k));},bytes(owner),bytes(recording));
        var tags=jdbc.query("SELECT tag_id,name_snapshot FROM recording_tag WHERE user_id=? AND recording_id=? ORDER BY tag_id",(rs,n)->{var b=java.nio.ByteBuffer.wrap(rs.getBytes(1));return Map.of("id",new UUID(b.getLong(),b.getLong()).toString(),"name_snapshot",rs.getString(2));},bytes(owner),bytes(recording));
        result.put("tag_ids",tags.stream().map(t->t.get("id")).toList());result.put("tags",tags);return result;
    }
    private record Patch(long revision,String state,Map<String,Object> fields,List<UUID> tags){@Override public String toString(){return "RecordingPatch[REDACTED]";}}
    private static Patch parse(JsonNode root){
        var base=root.get("base_revision");if(base==null || !base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();
        String state=null;var fields=new LinkedHashMap<String,Object>();List<UUID> tags=null;
        for(var e:root.properties()){
            String k=e.getKey();var v=e.getValue();
            switch(k){
                case "base_revision" -> {}
                case "metadata_state" -> state=choice(v,false,Set.of("DRAFT","SAVED"));
                case "title_snapshot","artist_snapshot","note" -> {
                    String raw=text(v,true);var kind=k.equals("note")?InputContracts.Field.NOTE:k.equals("title_snapshot")?InputContracts.Field.TITLE:InputContracts.Field.ARTIST;
                    if(raw==null && !k.equals("note")){fields.put(k,null);break;}
                    var checked=InputContracts.validate(kind,raw==null?"":raw);
                    if(!checked.valid())throw invalid();fields.put(k,checked.normalized());
                }
                case "version_code" -> fields.put(k,choice(v,false,Set.of("NORMAL","MR","LIVE")));
                case "key_mode" -> fields.put(k,choice(v,true,Set.of("ORIGINAL","MALE","FEMALE")));
                case "key_shift" -> fields.put(k,v.isNull()?null:integer(v,-12,12));
                case "condition_code" -> {String code=text(v,true);if(code!=null && !com.ksh321.songrecord.api.classifications.ConditionReference.valid(code))throw invalid();fields.put(k,code);}
                case "tag_ids" -> {
                    if(!v.isArray())throw invalid();var values=new TreeSet<UUID>(Comparator.comparing(UUID::toString));
                    for(var entry:v){try{String t=text(entry,false);UUID u=UUID.fromString(t);if(!u.toString().equals(t))throw invalid();if(!values.add(u))throw invalid();}catch(IllegalArgumentException ex){throw invalid();}}
                    tags=List.copyOf(values);
                }
                case "recorded_at" -> {String value=text(v,false);utc(value);fields.put(k,Instant.parse(value).toString());}
                case "timezone_id" -> {String value=text(v,false);if(value.length()>64 || !ZoneId.getAvailableZoneIds().contains(value))throw invalid();fields.put(k,value);}
                case "timezone_offset_minutes" -> fields.put(k,integer(v,-1080,1080));
                default -> throw invalid();
            }
        }
        return new Patch(base.asLong(),state,Collections.unmodifiableMap(fields),tags);
    }
    private static void validateMerged(Map<String,Object> values,String state){
        Object mode=values.get("key_mode"),shift=values.get("key_shift");
        if((mode==null)!=(shift==null) || mode!=null && (!(shift instanceof Number n) || n.intValue() < -12 || n.intValue()>12 || "ORIGINAL".equals(mode) && n.intValue()!=0))throw invalid();
        if("SAVED".equals(state) && (values.get("title_snapshot")==null || values.get("artist_snapshot")==null || mode==null))throw invalid();
    }
    private static LocalDateTime utc(String value){
        if(value==null || !value.matches("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?Z"))throw invalid();
        try{var time=OffsetDateTime.parse(value).toLocalDateTime();if(time.getYear()<1000 || time.getYear()>9999)throw invalid();return time;}catch(DateTimeException e){throw invalid();}
    }
    private static int integer(JsonNode v,int min,int max){if(!v.isIntegralNumber() || !v.canConvertToInt() || v.asInt()<min || v.asInt()>max)throw invalid();return v.asInt();}
    private static String text(JsonNode v,boolean nullable){if(v.isNull() && nullable)return null;if(!v.isTextual())throw invalid();return v.asText();}
    private static String choice(JsonNode v,boolean nullable,Set<String> choices){String s=text(v,nullable);if(s!=null && !choices.contains(s))throw invalid();return s;}
    private static UUID id(String s){try{var id=UUID.fromString(s);if(!id.toString().equals(s))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","녹음을 찾을 수 없습니다.");}}
    private static ApiException invalid(){return error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","녹음 수정 값을 확인해 주세요.");}
    private static ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message,false,Map.of());}
}
