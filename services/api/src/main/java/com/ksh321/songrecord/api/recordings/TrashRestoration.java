package com.ksh321.songrecord.api.recordings;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.retention.RetentionAssetVersions;
import com.ksh321.songrecord.api.songs.SongEditing;
import com.ksh321.songrecord.api.playlists.PlaylistService;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Restore only immutable batch members; later links, pins and representatives win. */
public final class TrashRestoration {
    private final JdbcTemplate db;private final AccountAccess access;private final IdempotentMutations mutations;
    private final AccountChanges changes;private final RevisionChanges revisions;private final RecordingEditing editing;private final Clock clock;
    private final JsonMapper json=new JsonMapper();
    public TrashRestoration(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,AccountChanges changes,RevisionChanges revisions,RecordingEditing editing,Clock clock){this.db=db;this.access=access;this.mutations=mutations;this.changes=changes;this.revisions=revisions;this.editing=editing;this.clock=clock;}
    public IdempotentMutations.Reply restore(String auth,String device,String operation,String rawBatch,String body){
        var account=access.authenticate(auth,device);UUID owner=account.principal().userId(),batch=id(rawBatch);
        var root=json.readTree(CanonicalRequest.canonical(body));
        if(!root.isObject() || !root.has("base_revision") || root.size()!=(root.has("item_ids")?2:1) || !root.get("base_revision").isIntegralNumber() || !root.get("base_revision").canConvertToLong() || root.get("base_revision").asLong()<1)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED");
        Set<UUID> requested=null;
        if(root.has("item_ids")){
            if(!root.get("item_ids").isArray() || root.get("item_ids").isEmpty() || root.get("item_ids").size()>100)throw error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED");
            requested=new HashSet<>();for(var node:root.get("item_ids")){if(!node.isTextual() || !requested.add(id(node.asText())))throw error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED");}
        }
        Set<UUID> selection=requested;
        return mutations.execute(account,operation,"POST","/v1/trash/"+batch+"/restore",body,()->changes.write(account,()->{
            var batches=db.queryForList("SELECT mode,deleted_at,purge_after FROM deletion_batch WHERE user_id=? AND id=?",bytes(owner),bytes(batch));if(batches.isEmpty())throw error(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND");
            var history=batches.getFirst();var deleted=time(history.get("deleted_at"));var expires=time(history.get("purge_after"));
            if(!LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).isBefore(expires))throw error(HttpStatus.CONFLICT,"TRASH_EXPIRED");
            db.update("INSERT INTO deletion_batch_work(user_id,batch_id,revision) SELECT ?,?,1 WHERE NOT EXISTS(SELECT 1 FROM deletion_batch_work WHERE user_id=? AND batch_id=?)",bytes(owner),bytes(batch),bytes(owner),bytes(batch));
            long version=db.queryForObject("SELECT revision FROM deletion_batch_work WHERE user_id=? AND batch_id=? FOR UPDATE",Long.class,bytes(owner),bytes(batch));
            if(version!=root.get("base_revision").asLong())throw new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT","최신 휴지통 묶음을 확인해 주세요.",false,Map.of("current_revision",version));
            if(version==Long.MAX_VALUE)throw error(HttpStatus.CONFLICT,"REVISION_LIMIT_REACHED");
            var all=db.queryForList("SELECT entity_type,entity_id,previous_song_id,previous_list_id,detached_link_revision FROM deletion_item WHERE user_id=? AND batch_id=? ORDER BY entity_type,entity_id",bytes(owner),bytes(batch));
            Set<UUID> selected=selection==null?new HashSet<>():new HashSet<>(selection);
            if(selection==null)for(var item:all)selected.add(uuid((byte[])item.get("entity_id")));
            for(UUID target:selected)if(all.stream().filter(i->Arrays.equals((byte[])i.get("entity_id"),bytes(target))).count()!=1)throw error(HttpStatus.BAD_REQUEST,"INVALID_TRASH_ITEM");
            var selectedSongs=new HashSet<UUID>();for(var item:all)if("SONG".equals(item.get("entity_type")) && selected.contains(uuid((byte[])item.get("entity_id"))))selectedSongs.add(uuid((byte[])item.get("entity_id")));
            for(var item:all)if("PLAYLIST_ITEM".equals(item.get("entity_type")) && item.get("previous_song_id")!=null && selectedSongs.contains(uuid((byte[])item.get("previous_song_id"))))selected.add(uuid((byte[])item.get("entity_id")));
            if("SONG_ONLY".equals(history.get("mode")) && all.stream().anyMatch(i->"SONG".equals(i.get("entity_type")) && selected.contains(uuid((byte[])i.get("entity_id")))))for(var item:all)if("RECORDING".equals(item.get("entity_type")))selected.add(uuid((byte[])item.get("entity_id")));
            var members=all.stream().filter(i->selected.contains(uuid((byte[])i.get("entity_id")))).toList();
            var songIds=new TreeSet<UUID>(Comparator.comparing(UUID::toString));
            for(var item:members){if("SONG".equals(item.get("entity_type")))songIds.add(uuid((byte[])item.get("entity_id")));if(item.get("previous_song_id")!=null)songIds.add(uuid((byte[])item.get("previous_song_id")));}
            var songs=new HashMap<UUID,Map<String,Object>>();
            for(UUID song:songIds)if(!db.queryForList("SELECT id FROM song WHERE user_id=? AND id=?",bytes(owner),bytes(song)).isEmpty())songs.put(song,revisions.lock(account,RevisionChanges.Resource.SONG,song.toString()));
            var records=new TreeMap<UUID,Map<String,Object>>(Comparator.comparing(UUID::toString));
            for(UUID recording:members.stream().filter(i->"RECORDING".equals(i.get("entity_type"))).map(i->uuid((byte[])i.get("entity_id"))).sorted(Comparator.comparing(UUID::toString)).toList())if(!db.queryForList("SELECT id FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(recording)).isEmpty())records.put(recording,revisions.lock(account,RevisionChanges.Resource.RECORDING,recording.toString()));
            var lists=new TreeMap<UUID,Map<String,Object>>(Comparator.comparing(UUID::toString));
            for(UUID parent:members.stream().filter(i->"PLAYLIST_ITEM".equals(i.get("entity_type")) && i.get("previous_list_id")!=null).map(i->uuid((byte[])i.get("previous_list_id"))).distinct().sorted(Comparator.comparing(UUID::toString)).toList())if(!db.queryForList("SELECT id FROM playlist WHERE user_id=? AND id=?",bytes(owner),bytes(parent)).isEmpty())lists.put(parent,revisions.lock(account,RevisionChanges.Resource.PLAYLIST,parent.toString()));
            var events=new ArrayList<AccountChanges.Change>();var restored=new ArrayList<Map<String,Object>>();var skipped=new ArrayList<Map<String,Object>>();var changedAssets=new ArrayList<UUID>();
            for(var item:members){if(!"SONG".equals(item.get("entity_type")))continue;UUID song=uuid((byte[])item.get("entity_id"));var current=songs.get(song);
                if(!eligible(current,deleted)){skipped.add(result("SONG",song,current==null?"PURGED":"STATE_CHANGED"));continue;}
                var updated=revisions.change(account,RevisionChanges.Resource.SONG,song.toString(),((Number)current.get("revision")).longValue(),old->db.update("UPDATE song SET lifecycle_state='ACTIVE',deleted_at=NULL,representative_recording_id=NULL WHERE user_id=? AND id=?",bytes(owner),bytes(song)));
                songs.put(song,updated);var wire=new LinkedHashMap<>(SongEditing.wire(updated));wire.put("deleted_at",null);restored.add(Map.of("entity_type","SONG","value",wire));events.add(new AccountChanges.Change(AccountChanges.Entity.SONG,song,((Number)updated.get("revision")).longValue(),AccountChanges.Operation.UPSERT,json.writeValueAsString(wire)));
            }
            for(var item:members){if(!"RECORDING".equals(item.get("entity_type")))continue;UUID recording=uuid((byte[])item.get("entity_id"));var current=records.get(recording);
                boolean only="SONG_ONLY".equals(history.get("mode"));
                if(current==null || (only?!"ACTIVE".equals(current.get("lifecycle_state")):!eligible(current,deleted))){skipped.add(result("RECORDING",recording,current==null?"PURGED":"STATE_CHANGED"));continue;}
                UUID previous=item.get("previous_song_id")==null?null:uuid((byte[])item.get("previous_song_id"));var parent=previous==null?null:songs.get(previous);
                boolean unchanged=current.get("song_id")==null && (item.get("detached_link_revision")==null || ((Number)item.get("detached_link_revision")).longValue()==((Number)current.get("link_revision")).longValue());
                boolean attach=unchanged && parent!=null && "ACTIVE".equals(parent.get("lifecycle_state"));
                if(only && !attach){skipped.add(result("RECORDING",recording,unchanged?"PARENT_UNAVAILABLE":"LINK_CHANGED"));continue;}
                if(attach && ((Number)current.get("link_revision")).longValue()==Long.MAX_VALUE)throw error(HttpStatus.CONFLICT,"LINK_REVISION_LIMIT_REACHED");
                if(!db.queryForList("SELECT recording_id FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='DELETING'",bytes(owner),bytes(recording)).isEmpty())throw error(HttpStatus.CONFLICT,"FILE_CLEANUP_IN_PROGRESS");
                revisions.change(account,RevisionChanges.Resource.RECORDING,recording.toString(),((Number)current.get("revision")).longValue(),old->{
                    if(attach)db.update("UPDATE recording SET lifecycle_state='ACTIVE',deleted_at=NULL,song_id=?,link_revision=link_revision+1 WHERE user_id=? AND id=?",bytes(previous),bytes(owner),bytes(recording));
                    else db.update("UPDATE recording SET lifecycle_state='ACTIVE',deleted_at=NULL WHERE user_id=? AND id=?",bytes(owner),bytes(recording));
                });
                changedAssets.add(recording);var wire=editing.snapshot(owner,recording);wire.put("deleted_at",null);restored.add(Map.of("entity_type","RECORDING","value",wire));events.add(new AccountChanges.Change(AccountChanges.Entity.RECORDING,recording,((Number)wire.get("revision")).longValue(),AccountChanges.Operation.UPSERT,json.writeValueAsString(wire)));
            }
            PlaylistService.restoreTrashedItems(db,revisions,account,batch,members,lists,restored,skipped,events,clock);
            RetentionAssetVersions.bump(db,owner,changedAssets);
            db.update("UPDATE deletion_batch_work SET revision=revision+1,updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND batch_id=? AND revision=?",bytes(owner),bytes(batch),version);
            return new AccountChanges.Batch<>(new IdempotentMutations.Reply(200,json.writeValueAsString(Map.of("batch_id",batch.toString(),"revision",version+1,"restored",restored,"skipped",skipped,"pin_reselection_required",true))),events);
        }).value());
    }
    static LocalDateTime time(Object value){if(value instanceof java.sql.Timestamp t)return t.toLocalDateTime();if(value instanceof LocalDateTime t)return t;throw new IllegalStateException("TRASH_TIME_INVALID");}
    private static boolean eligible(Map<String,Object> current,LocalDateTime date){return current!=null && "TRASHED".equals(current.get("lifecycle_state")) && Objects.equals(current.get("deleted_at"),date.toInstant(ZoneOffset.UTC).toString());}
    private static Map<String,Object> result(String type,UUID id,String reason){return Map.of("entity_type",type,"id",id.toString(),"reason",reason);}
    private static UUID id(String value){try{var id=UUID.fromString(value);if(!id.toString().equals(value))throw new IllegalArgumentException();return id;}catch(IllegalArgumentException|NullPointerException e){throw error(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED");}}
    private static ApiException error(HttpStatus status,String code){return new ApiException(status,code,"복원 가능한 항목과 서버 보관 기간을 확인해 주세요.",false,Map.of());}
}
