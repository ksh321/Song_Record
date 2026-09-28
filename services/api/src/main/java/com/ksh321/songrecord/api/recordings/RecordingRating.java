package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Recording-only rating, independent of song tier and physical file availability. */
public final class RecordingRating {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final RevisionChanges revisions;private final AccountChanges changes;private final RecordingEditing editing;private final JobQueue jobs;
    public RecordingRating(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,RevisionChanges revisions,AccountChanges changes,RecordingEditing editing,JobQueue jobs){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.revisions=revisions;this.changes=changes;this.editing=editing;this.jobs=jobs;
    }
    public IdempotentMutations.Reply patch(String auth,String device,String op,String id,String body){
        var account=access.authenticate(auth,device);UUID recording;
        try{recording=UUID.fromString(id);if(!recording.toString().equals(id))throw new IllegalArgumentException();}
        catch(IllegalArgumentException|NullPointerException e){throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","녹음을 찾을 수 없습니다.");}
        CanonicalRequest.canonical(body);var root=JSON.readTree(body);
        if(!root.isObject() || root.size()!=2 || !root.has("base_revision") || !root.has("tier"))throw invalid();
        var base=root.get("base_revision");if(!base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();
        var value=root.get("tier");if(!value.isNull() && (!value.isTextual() || !Set.of("S","A","B","C","D").contains(value.asText())))throw invalid();
        String tier=value.isNull()?null:value.asText();UUID owner=account.principal().userId();
        return mutations.execute(account,op,"PATCH","/v1/recordings/"+recording+"/tier",body,()->changes.write(account,()->{
            try{
                var updated=revisions.change(account,RevisionChanges.Resource.RECORDING,id,base.asLong(),current->{
                    if(!"ACTIVE".equals(current.get("lifecycle_state")))throw error(HttpStatus.CONFLICT,"RECORDING_NOT_ACTIVE","활성 녹음만 평가할 수 있습니다.");
                    if(!"SAVED".equals(current.get("metadata_state")))throw error(HttpStatus.CONFLICT,"RECORDING_NOT_SAVED","저장 완료 후 평가해 주세요.");
                    jdbc.update("UPDATE recording SET tier=? WHERE user_id=? AND id=?",tier,bytes(owner),bytes(recording));
                    if(!Objects.equals(current.get("tier"),tier) && current.get("song_id")!=null){
                        UUID song=UUID.fromString((String)current.get("song_id"));
                        jobs.enqueue(account,JobQueue.Type.POLICY_RECALCULATE,song,UUID.fromString(op),JSON.writeValueAsString(Map.of("song_id",song.toString(),"recording_id",id,"recording_revision",base.asLong()+1,"reason","RECORDING_TIER_CHANGED")));
                    }
                });
                String payload=JSON.writeValueAsString(editing.snapshot(owner,recording));
                return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,payload),List.of(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload)));
            }catch(ApiException e){
                if(!e.code().equals("REVISION_CONFLICT"))throw e;
                throw new ApiException(e.status(),e.code(),e.getMessage(),e.retryable(),Map.of("current_revision",e.details().get("current_revision"),"current",editing.snapshot(owner,recording)));
            }
        }).value());
    }
    private static ApiException invalid(){return error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","base_revision과 티어를 확인해 주세요.");}
    private static ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message,false,Map.of());}
}
