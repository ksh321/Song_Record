package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.songs.SongEditing;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Explicit relationship change; capture-time snapshots and physical file protection stay untouched. */
public final class RecordingLinking {
    private static final JsonMapper JSON=new JsonMapper();
    private final JdbcTemplate jdbc;private final AccountAccess access;private final IdempotentMutations mutations;
    private final RevisionChanges revisions;private final AccountChanges changes;private final RecordingEditing editing;private final JobQueue jobs;
    public RecordingLinking(JdbcTemplate jdbc,AccountAccess access,IdempotentMutations mutations,RevisionChanges revisions,AccountChanges changes,RecordingEditing editing,JobQueue jobs){
        this.jdbc=jdbc;this.access=access;this.mutations=mutations;this.revisions=revisions;this.changes=changes;this.editing=editing;this.jobs=jobs;
    }
    public IdempotentMutations.Reply patch(String auth,String device,String op,String id,String body){
        var account=access.authenticate(auth,device);UUID recording=uuid(id,true);UUID owner=account.principal().userId();
        CanonicalRequest.canonical(body);var root=JSON.readTree(body);
        if(!root.isObject() || root.size()!=2 || !root.has("base_revision") || !root.has("song_id"))throw invalid();
        var base=root.get("base_revision");if(!base.isIntegralNumber() || !base.canConvertToLong() || base.asLong()<1)throw invalid();
        var node=root.get("song_id");if(!node.isNull() && !node.isTextual())throw invalid();
        UUID target=node.isNull()?null:uuid(node.asText(),false);
        return mutations.execute(account,op,"PATCH","/v1/recordings/"+recording+"/song",body,()->changes.write(account,()->{
            // USER_SYNC makes this discovery stable until commit; explicit locks still follow SONG -> RECORDING.
            var rows=jdbc.queryForList("SELECT song_id FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(recording));
            if(rows.isEmpty())throw notFound();
            UUID previous=fromBytes((byte[])rows.getFirst().get("song_id"));
            var related=new TreeSet<UUID>(Comparator.comparing(UUID::toString));if(previous!=null)related.add(previous);if(target!=null)related.add(target);
            var songs=new HashMap<UUID,Map<String,Object>>();
            for(UUID song:related)songs.put(song,revisions.lock(account,RevisionChanges.Resource.SONG,song.toString()));
            if(target!=null && !"ACTIVE".equals(songs.get(target).get("lifecycle_state")))throw error("SONG_NOT_ACTIVE","활성 곡에만 연결할 수 있습니다.");
            var log=new ArrayList<AccountChanges.Change>();boolean moved=!Objects.equals(previous,target);
            try{
                var updated=revisions.change(account,RevisionChanges.Resource.RECORDING,id,base.asLong(),current->{
                    if(!"ACTIVE".equals(current.get("lifecycle_state")))throw error("RECORDING_NOT_ACTIVE","활성 녹음만 연결을 변경할 수 있습니다.");
                    if(!moved)return;
                    long link=((Number)current.get("link_revision")).longValue();
                    if(link==Long.MAX_VALUE)throw error("LINK_REVISION_LIMIT_REACHED","더 이상 연결 버전을 증가시킬 수 없습니다.");
                    if(previous!=null){
                        var old=songs.get(previous);
                        if(id.equals(old.get("representative_recording_id"))){
                            var song=revisions.change(account,RevisionChanges.Resource.SONG,previous.toString(),((Number)old.get("revision")).longValue(),ignored->
                                jdbc.update("UPDATE song SET representative_recording_id=NULL WHERE user_id=? AND id=?",bytes(owner),bytes(previous)));
                            log.add(new AccountChanges.Change(AccountChanges.Entity.SONG,previous,((Number)song.get("revision")).longValue(),AccountChanges.Operation.UPSERT,JSON.writeValueAsString(SongEditing.wire(song))));
                        }
                        clearSelection(owner,previous,recording);
                    }
                    // All composite FKs pointing at (owner, old song, recording) have been detached first.
                    jdbc.update("UPDATE recording SET song_id=?,link_revision=link_revision+1 WHERE user_id=? AND id=?",target==null?null:bytes(target),bytes(owner),bytes(recording));
                });
                if(moved)com.ksh321.songrecord.api.retention.RetentionAssetVersions.bump(jdbc,owner,List.of(recording));
                String payload=JSON.writeValueAsString(editing.snapshot(owner,recording));
                log.add(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,payload));
                return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,payload),log);
            }catch(ApiException e){
                if(!e.code().equals("REVISION_CONFLICT"))throw e;
                throw new ApiException(e.status(),e.code(),e.getMessage(),e.retryable(),Map.of("current_revision",e.details().get("current_revision"),"current",editing.snapshot(owner,recording)));
            }
        }).value());
    }
    private void clearSelection(UUID owner,UUID song,UUID recording){
        LockOrder.before(LockOrder.Rank.SONG_SELECTION,owner+"/"+song);
        var rows=jdbc.queryForList("SELECT representative_id,latest_id,lowest_tier_id,selection_revision FROM song_cloud_selection WHERE user_id=? AND song_id=? FOR UPDATE",bytes(owner),bytes(song));
        if(rows.isEmpty())return;var row=rows.getFirst();byte[] id=bytes(recording);
        var roles=List.of("representative_id","latest_id","lowest_tier_id").stream().filter(k->Arrays.equals((byte[])row.get(k),id)).toList();
        if(roles.isEmpty())return;
        if(((Number)row.get("selection_revision")).longValue()==Long.MAX_VALUE)throw error("SELECTION_REVISION_LIMIT_REACHED","보관 선정 버전을 확인해 주세요.");
        jdbc.update("UPDATE song_cloud_selection SET "+String.join(",",roles.stream().map(k->k+"=NULL").toList())+",selection_revision=selection_revision+1,updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND song_id=?",bytes(owner),bytes(song));
    }
    private static UUID fromBytes(byte[] data){if(data==null)return null;var b=java.nio.ByteBuffer.wrap(data);return new UUID(b.getLong(),b.getLong());}
    private static UUID uuid(String s,boolean resource){try{var id=UUID.fromString(s);if(!id.toString().equals(s))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){throw resource?notFound():invalid();}}
    private static ApiException error(String code,String message){return new ApiException(HttpStatus.CONFLICT,code,message,false,Map.of());}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","base_revision과 연결 곡을 확인해 주세요.",false,Map.of());}
    private static ApiException notFound(){return new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청한 자료를 찾을 수 없습니다.",false,Map.of());}
}
