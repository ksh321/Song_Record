package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Changes only the song pointer. Recording metadata and file availability are independent. */
public final class SongRepresentative {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final RevisionChanges revisions;private final AccountChanges changes;
    public SongRepresentative(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,RevisionChanges revisions,AccountChanges changes){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.revisions=revisions;this.changes=changes;
    }
    public IdempotentMutations.Reply put(String auth,String device,String op,String id,String body){
        var account=access.authenticate(auth,device);UUID song=SongEditing.parseId(id);var request=parse(body);UUID owner=account.principal().userId();
        try {
            return mutations.execute(account,op,"PUT","/v1/songs/"+song+"/representative",body,()->changes.write(account,()->{
                var updated=revisions.change(account,RevisionChanges.Resource.SONG,song.toString(),request.revision,current->{
                    String state=(String)current.get("lifecycle_state");
                    if(!"ACTIVE".equals(state))throw SongEditing.stateConflict(state);
                    if(request.recording!=null){
                        // USER_SYNC -> SONG -> RECORDING. Keep the eligibility row locked until commit.
                        LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/"+RevisionChanges.Resource.RECORDING.ordinal()+"/"+request.recording);
                        var rows=jdbc.queryForList("SELECT song_id,metadata_state,lifecycle_state FROM recording WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(request.recording));
                        if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청한 자료를 찾을 수 없습니다.",false,Map.of());
                        var recording=rows.getFirst();
                        if(!Arrays.equals((byte[])recording.get("song_id"),bytes(song)) || !"SAVED".equals(recording.get("metadata_state")) || !"ACTIVE".equals(recording.get("lifecycle_state")))
                            throw new ApiException(HttpStatus.CONFLICT,"REPRESENTATIVE_NOT_ELIGIBLE","같은 곡의 저장 완료된 활성 녹음만 지정할 수 있습니다.",false,Map.of());
                    }
                    jdbc.update("UPDATE song SET representative_recording_id=? WHERE user_id=? AND id=?",request.recording==null?null:bytes(request.recording),bytes(owner),bytes(song));
                });
                String payload=JSON.writeValueAsString(SongEditing.wire(updated));
                return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,payload),List.of(
                        new AccountChanges.Change(AccountChanges.Entity.SONG,song,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload)));
            }).value());
        }catch(ApiException e){
            if(!e.code().equals("REVISION_CONFLICT"))throw e;
            @SuppressWarnings("unchecked") var current=(Map<String,Object>)e.details().get("current");
            throw new ApiException(e.status(),e.code(),e.getMessage(),e.retryable(),Map.of("current_revision",e.details().get("current_revision"),"current",SongEditing.wire(current)));
        }
    }
    private record Selection(long revision,UUID recording){@Override public String toString(){return "RepresentativeSelection[REDACTED]";}}
    private static Selection parse(String body){
        var root=JSON.readTree(CanonicalRequest.canonical(body));
        if(!root.isObject() || root.size()!=2 || !root.has("base_revision") || !root.has("recording_id"))throw invalid();
        var base=root.get("base_revision");if(!base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();
        var value=root.get("recording_id");UUID recording=null;
        if(!value.isNull()){
            if(!value.isTextual())throw invalid();
            try{recording=UUID.fromString(value.asText());if(!recording.toString().equals(value.asText()))throw invalid();}
            catch(IllegalArgumentException e){throw invalid();}
        }
        return new Selection(base.asLong(),recording);
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","대표 녹음 지정 값을 확인해 주세요.",false,Map.of());}
}
