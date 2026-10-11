package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.CanonicalRequest;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.*;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Server-known scope only. Preview is not deletion authority or a client clock. */
public final class SongDeletionPreview {
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate transaction;
    private final JsonMapper json=new JsonMapper();
    public SongDeletionPreview(JdbcTemplate jdbc,AccountAccess access,PlatformTransactionManager manager){
        this.jdbc=jdbc;this.access=access;transaction=new TransactionTemplate(manager);
        transaction.setIsolationLevel(org.springframework.transaction.TransactionDefinition.ISOLATION_READ_COMMITTED);
    }
    public Map<String,Object> get(String authorization,String device,String songId){
        var account=access.authenticate(authorization,device);
        UUID song=id(songId);
        return transaction.execute(status->{
            var owner=access.revalidate(account).userId();
            // Same lock as AccountChanges: scope cannot straddle a concurrent domain write.
            lockOwner(owner);
            return snapshot(owner,song);
        });
    }
    /** Called inside the deletion mutation, BEFORE edits, under the account sync lock. */
    public void requireUnchanged(AccountAccess.Account account,UUID song,String previewVersion){
        if(!TransactionSynchronizationManager.isActualTransactionActive()
                || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))
            throw new IllegalStateException("Deletion preview comparison requires the mutation transaction");
        var owner=access.revalidate(account).userId();
        lockOwner(owner);
        var current=snapshot(owner,song);
        if(previewVersion==null || !previewVersion.matches("[0-9a-f]{64}")
                || !MessageDigest.isEqual(previewVersion.getBytes(StandardCharsets.US_ASCII),
                    ((String)current.get("preview_version")).getBytes(StandardCharsets.US_ASCII)))
            throw new ApiException(HttpStatus.CONFLICT,"DELETE_PREVIEW_CHANGED",
                    "삭제 대상이 바뀌었습니다. 미리보기를 다시 확인해 주세요.",false,Map.of());
    }
    private void lockOwner(UUID owner){
        com.ksh321.songrecord.api.locking.LockOrder.before(com.ksh321.songrecord.api.locking.LockOrder.Rank.USER_SYNC,owner.toString());
        if(jdbc.query("SELECT last_change_seq FROM user_sync_state WHERE user_id=? FOR UPDATE",(r,n)->r.getLong(1),bytes(owner)).size()!=1)
            throw new IllegalStateException("Account sync state is missing");
    }
    private Map<String,Object> snapshot(UUID owner,UUID song){
        var songs=jdbc.query("SELECT revision,representative_recording_id FROM song WHERE user_id=? AND id=? AND lifecycle_state='ACTIVE'",
                (r,n)->List.of(r.getLong(1),hex(r.getBytes(2))),bytes(owner),bytes(song));
        if(songs.size()!=1)throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","곡을 찾을 수 없습니다.",false,Map.of());
        var records=jdbc.query("SELECT r.id,r.revision,r.link_revision,r.metadata_state,a.cloud_state,a.cloud_revision,a.generation,a.verified_size FROM recording r LEFT JOIN recording_asset a ON a.user_id=r.user_id AND a.recording_id=r.id WHERE r.user_id=? AND r.song_id=? AND r.lifecycle_state='ACTIVE' ORDER BY r.id",
                (r,n)->{
                    var row=new LinkedHashMap<String,Object>();row.put("id",hex(r.getBytes(1)));row.put("revision",r.getLong(2));row.put("link_revision",r.getLong(3));row.put("metadata_state",r.getString(4));row.put("cloud_state",r.getString(5));
                    row.put("cloud_revision",r.getObject(6));row.put("generation",r.getObject(7));row.put("verified_size",r.getObject(8));return row;
                },bytes(owner),bytes(song));
        var pins=jdbc.query("SELECT p.slot_no,p.revision,p.current_recording_id,p.pending_recording_id FROM pin_slot p WHERE p.user_id=? AND (EXISTS(SELECT 1 FROM recording r WHERE r.user_id=p.user_id AND r.song_id=? AND r.lifecycle_state='ACTIVE' AND r.id=p.current_recording_id) OR EXISTS(SELECT 1 FROM recording r WHERE r.user_id=p.user_id AND r.song_id=? AND r.lifecycle_state='ACTIVE' AND r.id=p.pending_recording_id)) ORDER BY p.slot_no",
                (r,n)->List.of(r.getInt(1),r.getLong(2),hex(r.getBytes(3)),hex(r.getBytes(4))),bytes(owner),bytes(song),bytes(song));
        var linked=new HashSet<String>();for(var r:records)linked.add((String)r.get("id"));
        var pinned=new HashSet<String>();for(var p:pins){for(int i=2;i<=3;i++)if(linked.contains(p.get(i)))pinned.add((String)p.get(i));}
        long size=0;for(var r:records)if(Set.of("STORED","DELETING").contains(Objects.toString(r.get("cloud_state"),""))){
            if(!(r.get("verified_size") instanceof Number bytes) || bytes.longValue()<1)throw new IllegalStateException("Stored asset size is missing");
            size=Math.addExact(size,bytes.longValue());
        }
        var basis=new LinkedHashMap<String,Object>();basis.put("schema",1);basis.put("owner",owner.toString());basis.put("song",song.toString());basis.put("song_state",songs.getFirst());basis.put("recordings",records);basis.put("pins",pins);
        String token;
        try{token=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(CanonicalRequest.canonical(json.writeValueAsString(basis)).getBytes(StandardCharsets.UTF_8)));}
        catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}
        return Map.of("recording_count",records.size(),"server_bytes",size,"pinned_count",pinned.size(),"preview_version",token,"scope","SERVER_SYNCED_ONLY");
    }
    private static String hex(byte[] bytes){return bytes==null?"":HexFormat.of().formatHex(bytes);}
    private static UUID id(String value){
        try{UUID id=UUID.fromString(value);if(!id.toString().equals(value))throw new IllegalArgumentException();return id;}
        catch(IllegalArgumentException|NullPointerException e){throw new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","곡 ID를 확인해 주세요.",false,Map.of());}
    }
}
