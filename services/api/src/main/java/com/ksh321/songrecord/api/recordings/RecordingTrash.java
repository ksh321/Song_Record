package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.songs.SongEditing;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** A logical, revision-bound deletion; bytes are retained until server purge. */
public final class RecordingTrash {
    private final JdbcTemplate db; private final AccountAccess access; private final IdempotentMutations mutations;
    private final AccountChanges changes; private final RevisionChanges revisions; private final RecordingEditing editing; private final Clock clock;
    private final JsonMapper json=new JsonMapper();
    public RecordingTrash(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,AccountChanges changes,RevisionChanges revisions,RecordingEditing editing,Clock clock){this.db=db;this.access=access;this.mutations=mutations;this.changes=changes;this.revisions=revisions;this.editing=editing;this.clock=clock;}
    public IdempotentMutations.Reply trash(String auth,String device,String operation,String id,String body){
        var account=access.authenticate(auth,device);UUID owner=account.principal().userId(),recording=parseId(id);
        var root=json.readTree(CanonicalRequest.canonical(body));
        if(!root.isObject() || root.size()!=2 || !root.has("base_revision") || !root.get("base_revision").isIntegralNumber() || !root.get("base_revision").canConvertToLong() || root.get("base_revision").asLong()<1 || !root.has("pin_release_confirmed") || !root.get("pin_release_confirmed").isBoolean())throw failure(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED");
        var effects=new TrashRecordingEffects(db,clock);
        return mutations.execute(account,operation,"POST","/v1/recordings/"+recording+"/trash",body,()->{
            LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");db.queryForMap("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE");
            return changes.write(account,()->{
                effects.lockBudget(owner);
                var rows=db.queryForList("SELECT song_id FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(recording));
                if(rows.isEmpty())throw failure(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND");
                UUID song=rows.getFirst().get("song_id")==null?null:uuid((byte[])rows.getFirst().get("song_id"));
                var currentSong=song==null?null:revisions.lock(account,RevisionChanges.Resource.SONG,song.toString());
                var current=revisions.lock(account,RevisionChanges.Resource.RECORDING,id);
                if(!"ACTIVE".equals(current.get("lifecycle_state")))throw failure(HttpStatus.CONFLICT,"RECORDING_NOT_ACTIVE");
                if(((Number)current.get("revision")).longValue()!=root.get("base_revision").asLong())throw new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT","최신 녹음을 확인해 주세요.",false,Map.of("current_revision",current.get("revision"),"current",editing.snapshot(owner,recording)));
                long link=((Number)current.get("link_revision")).longValue();if(song!=null && link==Long.MAX_VALUE)throw failure(HttpStatus.CONFLICT,"LINK_REVISION_LIMIT_REACHED");
                if(!db.queryForList("SELECT recording_id FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='DELETING'",bytes(owner),bytes(recording)).isEmpty())throw failure(HttpStatus.CONFLICT,"FILE_CLEANUP_IN_PROGRESS");
                if(!root.get("pin_release_confirmed").asBoolean() && !db.queryForList("SELECT slot_no FROM pin_slot WHERE user_id=? AND (current_recording_id=? OR pending_recording_id=?)",bytes(owner),bytes(recording),bytes(recording)).isEmpty())throw failure(HttpStatus.CONFLICT,"PIN_RELEASE_CONFIRMATION_REQUIRED");
                var events=new ArrayList<AccountChanges.Change>();
                if(song!=null){
                    if(id.equals(currentSong.get("representative_recording_id"))){
                        var updatedSong=revisions.change(account,RevisionChanges.Resource.SONG,song.toString(),((Number)currentSong.get("revision")).longValue(),old->db.update("UPDATE song SET representative_recording_id=NULL WHERE user_id=? AND id=?",bytes(owner),bytes(song)));
                        events.add(new AccountChanges.Change(AccountChanges.Entity.SONG,song,((Number)updatedSong.get("revision")).longValue(),AccountChanges.Operation.UPSERT,json.writeValueAsString(SongEditing.wire(updatedSong))));
                    }
                    LockOrder.before(LockOrder.Rank.SONG_SELECTION,owner+"/"+song);
                    var selections=db.queryForList("SELECT representative_id,latest_id,lowest_tier_id,selection_revision FROM song_cloud_selection WHERE user_id=? AND song_id=? FOR UPDATE",bytes(owner),bytes(song));
                    if(!selections.isEmpty()){
                        var selection=selections.getFirst();var roles=List.of("representative_id","latest_id","lowest_tier_id").stream().filter(k->Arrays.equals((byte[])selection.get(k),bytes(recording))).toList();
                        if(!roles.isEmpty()){
                            if(((Number)selection.get("selection_revision")).longValue()==Long.MAX_VALUE)throw failure(HttpStatus.CONFLICT,"SELECTION_REVISION_LIMIT_REACHED");
                            db.update("UPDATE song_cloud_selection SET "+String.join(",",roles.stream().map(k->k+"=NULL").toList())+",selection_revision=selection_revision+1,updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND song_id=?",bytes(owner),bytes(song));
                        }
                    }
                }
                UUID batch=UUID.randomUUID();var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);
                db.update("INSERT INTO deletion_batch(id,user_id,op_id,mode,deleted_at,purge_after,preview_version) VALUES(?,?,?,'RECORDING',?,?,?)",bytes(batch),bytes(owner),bytes(UUID.fromString(operation)),now,now.plusDays(7),"revision:"+root.get("base_revision").asLong());
                db.update("INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,detached_link_revision) VALUES(?,?,'RECORDING',?,?,?)",bytes(batch),bytes(owner),bytes(recording),song==null?null:bytes(song),song==null?null:link+1);
                revisions.change(account,RevisionChanges.Resource.RECORDING,id,root.get("base_revision").asLong(),old->db.update("UPDATE recording SET lifecycle_state='TRASHED',deleted_at=?,song_id=NULL,link_revision=link_revision+? WHERE user_id=? AND id=?",now,song==null?0:1,bytes(owner),bytes(recording)));
                effects.apply(owner,List.of(recording));
                var wire=editing.snapshot(owner,recording);wire.put("deleted_at",now.toInstant(ZoneOffset.UTC).toString());
                events.add(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)wire.get("revision")).longValue(),AccountChanges.Operation.UPSERT,json.writeValueAsString(wire)));
                return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,json.writeValueAsString(Map.of("batch_id",batch.toString(),"deleted_at",now.toInstant(ZoneOffset.UTC).toString(),"purge_after",now.plusDays(7).toInstant(ZoneOffset.UTC).toString(),"recording",wire))),events);
            }).value();
        });
    }
    private static ApiException failure(HttpStatus status,String code){return new ApiException(status,code,"녹음 삭제 상태와 고정 해제 확인을 확인해 주세요.",false,Map.of());}
    private static UUID parseId(String value){try{var id=UUID.fromString(value);if(!id.toString().equals(value))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){throw failure(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND");}}
}
