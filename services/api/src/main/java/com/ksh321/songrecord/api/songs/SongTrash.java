package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.playlists.PlaylistService;
import com.ksh321.songrecord.api.recordings.RecordingEditing;
import com.ksh321.songrecord.api.uploads.OrphanUploads;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Song-only trash preserves active recordings, files and pins in the same mutation. */
public final class SongTrash {
    private final JdbcTemplate db;
    private final AccountAccess access;
    private final IdempotentMutations mutations;
    private final AccountChanges changes;
    private final RevisionChanges revisions;
    private final SongDeletionPreview preview;
    private final RecordingEditing recordings;
    private final Clock clock;
    private final JsonMapper json=new JsonMapper();
    public SongTrash(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,AccountChanges changes,RevisionChanges revisions,SongDeletionPreview preview,RecordingEditing recordings,Clock clock){
        this.db=db;this.access=access;this.mutations=mutations;this.changes=changes;this.revisions=revisions;this.preview=preview;this.recordings=recordings;this.clock=clock;
    }
    public IdempotentMutations.Reply trash(String auth,String device,String operation,String id,String body){
        var account=access.authenticate(auth,device);UUID song=SongEditing.parseId(id),owner=account.principal().userId();
        var root=json.readTree(CanonicalRequest.canonical(body));
        if(!root.isObject() || root.size()!=2 || !root.has("mode") || !root.has("preview_version")
                || !root.get("mode").isTextual() || !Set.of("SONG_ONLY","SONG_AND_RECORDINGS").contains(root.get("mode").asText())
                || !root.get("preview_version").isTextual() || !root.get("preview_version").asText().matches("[0-9a-f]{64}"))throw invalid();
        String mode=root.get("mode").asText();boolean together=mode.equals("SONG_AND_RECORDINGS");
        var effects=new com.ksh321.songrecord.api.recordings.TrashRecordingEffects(db,clock);
        return mutations.execute(account,operation,"POST","/v1/songs/"+song+"/trash",body,()->{
            if(together){LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");db.queryForMap("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE");}
            return changes.write(account,()->{
            if(together)effects.lockBudget(owner);
            preview.requireUnchanged(account,song,root.get("preview_version").asText());
            if(!db.queryForList("SELECT r.id FROM recording r JOIN recording_asset a ON a.user_id=r.user_id AND a.recording_id=r.id WHERE r.user_id=? AND r.song_id=? AND r.lifecycle_state='ACTIVE' AND a.cloud_state='DELETING'",bytes(owner),bytes(song)).isEmpty())throw conflict("FILE_CLEANUP_IN_PROGRESS");
            var current=revisions.lock(account,RevisionChanges.Resource.SONG,id);
            var targets=db.query("SELECT id,revision,link_revision FROM recording WHERE user_id=? AND song_id=? AND lifecycle_state='ACTIVE' ORDER BY id",(r,n)->new Target(uuid(r.getBytes(1)),r.getLong(2),r.getLong(3)),bytes(owner),bytes(song));
            for(var target:targets){if(target.linkRevision==Long.MAX_VALUE)throw conflict("LINK_REVISION_LIMIT_REACHED");revisions.lock(account,RevisionChanges.Resource.RECORDING,target.id.toString());}
            // Pre-lock every aggregate before selection/assets. Re-acquisition is allowed by LockOrder.
            var parents=db.query("SELECT DISTINCT p.id FROM playlist p JOIN playlist_item i ON i.user_id=p.user_id AND i.playlist_id=p.id WHERE p.user_id=? AND p.deleted_at IS NULL AND i.song_id=? AND i.hidden_by_batch_id IS NULL ORDER BY p.id",(r,n)->uuid(r.getBytes(1)),bytes(owner),bytes(song));
            for(UUID parent:parents)revisions.lock(account,RevisionChanges.Resource.PLAYLIST,parent.toString());
            UUID batch=UUID.randomUUID();var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);var expiry=now.plusDays(7);
            db.update("INSERT INTO deletion_batch(id,user_id,op_id,mode,deleted_at,purge_after,preview_version) VALUES(?,?,?,?,?,?,?)",bytes(batch),bytes(owner),bytes(UUID.fromString(operation)),mode,now,expiry,root.get("preview_version").asText());
            db.update("INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id) VALUES(?,?,'SONG',?)",bytes(batch),bytes(owner),bytes(song));
            var updated=revisions.change(account,RevisionChanges.Resource.SONG,id,((Number)current.get("revision")).longValue(),old->db.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=?,representative_recording_id=NULL WHERE user_id=? AND id=?",now,bytes(owner),bytes(song)));
            LockOrder.before(LockOrder.Rank.SONG_SELECTION,owner+"/"+song);
            var selections=db.queryForList("SELECT selection_revision FROM song_cloud_selection WHERE user_id=? AND song_id=? FOR UPDATE",bytes(owner),bytes(song));
            if(!selections.isEmpty()){
                if(((Number)selections.getFirst().get("selection_revision")).longValue()==Long.MAX_VALUE)throw conflict("SELECTION_REVISION_LIMIT_REACHED");
                db.update("UPDATE song_cloud_selection SET representative_id=NULL,latest_id=NULL,lowest_tier_id=NULL,selection_revision=selection_revision+1,updated_at=? WHERE user_id=? AND song_id=?",now,bytes(owner),bytes(song));
            }
            var events=new ArrayList<AccountChanges.Change>();var detached=new ArrayList<Map<String,Object>>();
            var songWire=new LinkedHashMap<>(SongEditing.wire(updated));songWire.put("deleted_at",now.toInstant(ZoneOffset.UTC).toString());
            events.add(new AccountChanges.Change(AccountChanges.Entity.SONG,song,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,json.writeValueAsString(songWire)));
            for(var target:targets){
                db.update("INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,detached_link_revision) VALUES(?,?,'RECORDING',?,?,?)",bytes(batch),bytes(owner),bytes(target.id),bytes(song),target.linkRevision+1);
                revisions.change(account,RevisionChanges.Resource.RECORDING,target.id.toString(),target.revision,old->{
                    if(together)db.update("UPDATE recording SET song_id=NULL,link_revision=link_revision+1,lifecycle_state='TRASHED',deleted_at=? WHERE user_id=? AND id=?",now,bytes(owner),bytes(target.id));
                    else db.update("UPDATE recording SET song_id=NULL,link_revision=link_revision+1 WHERE user_id=? AND id=?",bytes(owner),bytes(target.id));
                });
                var wire=recordings.snapshot(owner,target.id);if(together)wire.put("deleted_at",now.toInstant(ZoneOffset.UTC).toString());detached.add(wire);events.add(new AccountChanges.Change(AccountChanges.Entity.RECORDING,target.id,((Number)wire.get("revision")).longValue(),AccountChanges.Operation.UPSERT,json.writeValueAsString(wire)));
            }
            for(UUID parent:parents)db.update("INSERT INTO deletion_item(batch_id,user_id,entity_type,entity_id,previous_song_id,previous_list_id) SELECT ?,?,'PLAYLIST_ITEM',id,song_id,playlist_id FROM playlist_item WHERE user_id=? AND playlist_id=? AND song_id=? AND hidden_by_batch_id IS NULL",bytes(batch),bytes(owner),bytes(owner),bytes(parent),bytes(song));
            events.addAll(PlaylistService.hideTrashedSong(db,revisions,account,song,batch,clock));
            if(together)effects.apply(owner,targets.stream().map(t->t.id).toList());
            else OrphanUploads.preserve(db,owner,targets.stream().map(t->t.id).toList(),clock);
            return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,json.writeValueAsString(Map.of("batch_id",batch.toString(),"mode",mode,"deleted_at",now.toInstant(ZoneOffset.UTC).toString(),"purge_after",expiry.toInstant(ZoneOffset.UTC).toString(),"song",songWire,"recordings",detached))),events);
        }).value();});
    }
    private record Target(UUID id,long revision,long linkRevision){}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","삭제 모드와 미리보기를 확인해 주세요.",false,Map.of());}
    private static ApiException conflict(String code){return new ApiException(HttpStatus.CONFLICT,code,"삭제 대상의 버전을 확인해 주세요.",false,Map.of());}
}
