package com.ksh321.songrecord.api.recordings;

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
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Accepts the device's completed-file specification, not proof of a verified server copy. */
public final class RecordingSaving {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final RevisionChanges revisions;private final AccountChanges changes;private final RecordingDrafts drafts;
    public RecordingSaving(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,RevisionChanges revisions,AccountChanges changes,RecordingDrafts drafts){this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.revisions=revisions;this.changes=changes;this.drafts=drafts;}
    public IdempotentMutations.Reply save(String auth,String device,String op,String id,String body){
        var account=access.authenticate(auth,device);UUID recording;
        try{recording=UUID.fromString(id);if(!recording.toString().equals(id))throw new IllegalArgumentException();}catch(IllegalArgumentException|NullPointerException e){throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","녹음을 찾을 수 없습니다.");}
        var request=parse(body);UUID owner=account.principal().userId();
        return mutations.execute(account,op,"PATCH","/v1/recordings/"+recording,body,()->changes.write(account,()->{
            var updated=revisions.change(account,RevisionChanges.Resource.RECORDING,recording.toString(),request.revision,current->{
                if(!"ACTIVE".equals(current.get("lifecycle_state")))throw error(HttpStatus.CONFLICT,"RECORDING_NOT_ACTIVE","활성 녹음만 저장 완료할 수 있습니다.");
                if(!"DRAFT".equals(current.get("metadata_state")))throw error(HttpStatus.CONFLICT,"RECORDING_ALREADY_SAVED","이미 저장 완료된 녹음입니다.");
                var merged=new LinkedHashMap<>(current);merged.putAll(request.fields);validateSaved(merged);
                // Lock on the parent recording serializes all participating file-spec writers.
                var existing=jdbc.queryForList("SELECT recording_id FROM recording_file_spec WHERE user_id=? AND recording_id=?",bytes(owner),bytes(recording));
                if(!existing.isEmpty())throw error(HttpStatus.CONFLICT,"FILE_SPEC_ALREADY_EXISTS","기존 파일 명세를 확인해 주세요.");
                var f=request.file;
                jdbc.update("INSERT INTO recording_file_spec(recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity) VALUES(?,?,?,?,?,?,?,?,?)",bytes(recording),bytes(owner),f.get("sha256"),f.get("size_bytes"),f.get("duration_ms"),f.get("codec"),f.get("sample_rate"),f.get("channels"),f.get("capture_integrity"));
                // Actual V2 trigger requires the specification to exist before this state change.
                jdbc.update("UPDATE recording SET title_snapshot=?,artist_snapshot=?,version_code=?,key_mode=?,key_shift=?,note=?,metadata_state='SAVED' WHERE user_id=? AND id=?",merged.get("title_snapshot"),merged.get("artist_snapshot"),merged.get("version_code"),merged.get("key_mode"),merged.get("key_shift"),merged.get("note"),bytes(owner),bytes(recording));
                RecordingQueryKeys.replace(jdbc,owner,recording,(String)merged.get("title_snapshot"));
            });
            var snapshot=new LinkedHashMap<>(drafts.snapshot(owner,recording));snapshot.put("file",request.file);
            String payload=JSON.writeValueAsString(snapshot);
            return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,payload),List.of(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload)));
        }).value());
    }
    private record Save(long revision,Map<String,Object> fields,Map<String,Object> file){@Override public String toString(){return "RecordingSave[REDACTED]";}}
    private static Save parse(String body){
        CanonicalRequest.canonical(body);var root=JSON.readTree(body);if(!root.isObject())throw invalid();
        var base=root.get("base_revision");if(base==null || !base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();
        if(!"SAVED".equals(text(root.get("metadata_state"))))throw invalid();
        var fields=new LinkedHashMap<String,Object>();
        for(var entry:root.properties()){
            String name=entry.getKey();var value=entry.getValue();
            switch(name){
                case "base_revision","metadata_state","file" -> {}
                case "title_snapshot","artist_snapshot","note" -> {
                    String raw=name.equals("note") && value.isNull()?"":text(value);
                    var kind=name.equals("note")?InputContracts.Field.NOTE:name.equals("title_snapshot")?InputContracts.Field.TITLE:InputContracts.Field.ARTIST;
                    var validated=InputContracts.validate(kind,raw);if(!validated.valid())throw invalid();fields.put(name,validated.normalized());
                }
                case "version_code","key_mode" -> fields.put(name,text(value));
                case "key_shift" -> {if(!value.isIntegralNumber() || !value.canConvertToInt())throw invalid();fields.put(name,value.asInt());}
                default -> throw invalid();
            }
        }
        var file=root.get("file");if(file==null || !file.isObject() || file.size()!=7)throw invalid();
        var f=new LinkedHashMap<String,Object>();
        f.put("size_bytes",number(file.get("size_bytes"),1,6291456));f.put("duration_ms",number(file.get("duration_ms"),1,361000));
        String hash=text(file.get("sha256"));if(!hash.matches("[0-9a-f]{64}"))throw invalid();f.put("sha256",hash);
        String codec=text(file.get("codec"));if(!codec.equals("AAC_LC"))throw invalid();f.put("codec",codec);
        f.put("sample_rate",number(file.get("sample_rate"),48000,48000));f.put("channels",number(file.get("channels"),1,1));
        String integrity=text(file.get("capture_integrity"));if(!Set.of("VALIDATED","RECOVERED").contains(integrity))throw invalid();f.put("capture_integrity",integrity);
        return new Save(base.asLong(),Collections.unmodifiableMap(fields),Collections.unmodifiableMap(f));
    }
    private static void validateSaved(Map<String,Object> values){
        for(String name:List.of("title_snapshot","artist_snapshot")){Object value=values.get(name);if(!(value instanceof String text) || !InputContracts.validate(name.equals("title_snapshot")?InputContracts.Field.TITLE:InputContracts.Field.ARTIST,text).valid())throw invalid();}
        if(!Set.of("NORMAL","MR","LIVE").contains(Objects.toString(values.get("version_code"),"")))throw invalid();
        Object mode=values.get("key_mode"),shift=values.get("key_shift");
        if(!Set.of("ORIGINAL","MALE","FEMALE").contains(Objects.toString(mode,"")) || !(shift instanceof Number n) || n.intValue() < -12 || n.intValue()>12 || "ORIGINAL".equals(mode) && n.intValue()!=0)throw invalid();
    }
    private static long number(JsonNode value,long min,long max){if(value==null || !value.isIntegralNumber() || !value.canConvertToLong() || value.asLong()<min || value.asLong()>max)throw invalid();return value.asLong();}
    private static String text(JsonNode value){if(value==null || !value.isTextual())throw invalid();return value.asText();}
    private static ApiException invalid(){return error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","저장 완료에 필요한 입력과 파일 명세를 확인해 주세요.");}
    private static ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message,false,Map.of());}
}
