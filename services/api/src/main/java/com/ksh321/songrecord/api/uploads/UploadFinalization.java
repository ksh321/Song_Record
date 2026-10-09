package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.retention.*;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import java.time.*;import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Object I/O precedes JobQueue's fenced DB transaction. Never replaces an existing asset. */
public final class UploadFinalization implements AudioValidator.Next {
    private final JdbcTemplate db;private final UploadFinalObjects objects;private final Clock clock;private final RetentionRoles roles;
    public UploadFinalization(JdbcTemplate db,UploadFinalObjects objects,Clock clock){this.db=db;this.objects=objects;this.clock=clock;roles=new RetentionRoles(new RetentionCandidates(db));}
    public Runnable prepare(JobQueue.Lease lease,AudioValidator.Validated audio)throws Exception{
        LockOrder.requireOutsideTransaction();var row=attempt(lease);requireLease(lease);
        UUID recording=uuid((byte[])row.get("recording_id"));var key=finalKey(lease.userId(),recording,(String)row.get("final_key"));
        if(!"VERIFYING".equals(row.get("state")) || audio.bytes().remaining()!=n(row,"expected_size") || !audio.sha256().equals(row.get("expected_sha256")))throw new IllegalStateException("UPLOAD_STATE_CONFLICT");
        if(!eligible(lease.userId(),recording))throw new IllegalStateException("NOT_CLOUD_TARGET");
        objects.ensure(key,audio.bytes(),audio.sha256());
        requireLease(lease);
        return ()->commit(lease,audio.sha256(),audio.bytes().remaining());
    }
    private void commit(JobQueue.Lease lease,String hash,long size){
        UUID owner=lease.userId();lock(owner);
        var row=attemptLocked(lease);if("COMMITTED".equals(row.get("state")))return;
        requireLease(lease);
        UUID recording=uuid((byte[])row.get("recording_id"));
        LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/"+recording);
        var recordingRows=db.queryForList("SELECT id FROM recording WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(recording));
        if(recordingRows.size()!=1 || !eligible(owner,recording) || !instant(row.get("expires_at")).isAfter(clock.instant()) || !"VERIFYING".equals(row.get("state")))throw new IllegalStateException("UPLOAD_AUTHORITY_LOST");
        var spec=db.queryForList("SELECT size_bytes,sha256 FROM recording_file_spec WHERE user_id=? AND recording_id=?",bytes(owner),bytes(recording));
        if(spec.size()!=1 || n(spec.getFirst(),"size_bytes")!=size || !hash.equals(spec.getFirst().get("sha256")))throw new IllegalStateException("FILE_SPEC_MISMATCH");
        LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+recording);
        var assets=db.queryForList("SELECT cloud_state,cloud_revision,generation FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(recording));
        long revision=assets.isEmpty()?1:n(assets.getFirst(),"cloud_revision");
        if(revision!=n(row,"policy_revision") || (!assets.isEmpty() && Set.of("STORED","DELETING").contains(assets.getFirst().get("cloud_state"))))throw new IllegalStateException("UPLOAD_POLICY_CHANGED");
        UUID generation=finalKey(owner,recording,(String)row.get("final_key")).generation();
        var now=java.sql.Timestamp.from(clock.instant());
        if(assets.isEmpty())db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at,cloud_revision) VALUES(?,?,'STORED',?,?,?,?,?,?)",bytes(recording),bytes(owner),row.get("final_key"),bytes(generation),size,hash,now,Math.incrementExact(revision));
        else db.update("UPDATE recording_asset SET cloud_state='STORED',blocked_reason=NULL,object_key=?,generation=?,verified_size=?,sha256=?,stored_at=?,cloud_revision=?,updated_at=? WHERE user_id=? AND recording_id=?",row.get("final_key"),bytes(generation),size,hash,now,Math.incrementExact(revision),now,bytes(owner),bytes(recording));
        if(db.update("UPDATE storage_usage SET reserved_bytes=reserved_bytes-?,used_bytes=used_bytes+?,revision=revision+1,updated_at=? WHERE user_id=? AND reserved_bytes>=?",size,size,now,bytes(owner),size)!=1 || db.update("UPDATE global_storage_usage SET reserved_bytes=reserved_bytes-?,used_bytes=used_bytes+?,revision=revision+1,updated_at=? WHERE id=1 AND reserved_bytes>=?",size,size,now,size)!=1)throw new IllegalStateException("UPLOAD_ACCOUNTING_MISMATCH");
        publishAsset(owner,recording,Math.incrementExact(revision));
        db.update("UPDATE recording_upload SET state='COMMITTED',active_slot=NULL,reservation_released_at=?,error_code=NULL,updated_at=? WHERE user_id=? AND id=?",now,now,bytes(owner),bytes(lease.aggregateId()));
    }
    private void publishAsset(UUID owner,UUID recording,long revision){
        var source=db.queryForMap("SELECT recording_id,cloud_state,blocked_reason,generation,verified_size,sha256,stored_at,cloud_revision,created_at,updated_at FROM recording_asset WHERE user_id=? AND recording_id=?",bytes(owner),bytes(recording));
        var payload=new LinkedHashMap<String,Object>();
        for(var e:source.entrySet()){
            Object value=e.getValue();if(value instanceof byte[] b)value=uuid(b).toString();
            if(value instanceof java.sql.Timestamp || value instanceof LocalDateTime)value=instant(value).truncatedTo(java.time.temporal.ChronoUnit.MILLIS).toString();
            payload.put(e.getKey().toLowerCase(Locale.ROOT),value);
        }
        long sequence=db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner));long next=Math.incrementExact(sequence);
        var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(java.time.temporal.ChronoUnit.MILLIS);
        db.update("INSERT INTO change_log(user_id,change_seq,entity_type,entity_id,revision,operation,payload,created_at,expires_at) VALUES(?,?,'RECORDING_ASSET',?,?,'UPSERT',?,?,?)",bytes(owner),next,bytes(recording),revision,new tools.jackson.databind.json.JsonMapper().writeValueAsString(payload),now,now.plusDays(90));
        if(db.update("UPDATE user_sync_state SET last_change_seq=?,updated_at=? WHERE user_id=? AND last_change_seq=?",next,now,bytes(owner),sequence)!=1)throw new IllegalStateException("UPLOAD_SYNC_CONFLICT");
    }
    void lock(UUID owner){
        LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");db.queryForMap("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE");
        LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());db.queryForMap("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));
        LockOrder.before(LockOrder.Rank.ENTITLEMENT,owner+"/");db.queryForMap("SELECT user_id FROM user_entitlement WHERE user_id=? FOR UPDATE",bytes(owner));
        LockOrder.before(LockOrder.Rank.STORAGE_USAGE,owner+"/");db.queryForMap("SELECT user_id FROM storage_usage WHERE user_id=? FOR UPDATE",bytes(owner));
    }
    boolean eligible(UUID owner,UUID recording){
        var rows=db.queryForList("SELECT r.song_id FROM recording r JOIN app_user u ON u.id=r.user_id LEFT JOIN song s ON s.id=r.song_id AND s.user_id=r.user_id WHERE r.user_id=? AND r.id=? AND u.status='ACTIVE' AND r.lifecycle_state='ACTIVE' AND r.metadata_state='SAVED' AND (r.song_id IS NULL OR s.lifecycle_state='ACTIVE')",bytes(owner),bytes(recording));
        if(rows.size()!=1)return false;
        if(!db.queryForList("SELECT slot_no FROM pin_slot WHERE user_id=? AND (current_recording_id=? OR pending_recording_id=?)",bytes(owner),bytes(recording),bytes(recording)).isEmpty() || !db.queryForList("SELECT recording_id FROM cloud_hold WHERE user_id=? AND recording_id=?",bytes(owner),bytes(recording)).isEmpty())return true;
        if(rows.getFirst().get("song_id")==null)return false;UUID song=uuid((byte[])rows.getFirst().get("song_id"));
        return roles.representative(owner,song).map(s->s.candidate().recordingId().equals(recording)).orElse(false) || roles.latest(owner,song).map(s->s.candidate().recordingId().equals(recording)).orElse(false) || roles.lowestTier(owner,song).map(s->s.candidate().recordingId().equals(recording)).orElse(false);
    }
    Map<String,Object> attempt(JobQueue.Lease lease){if(lease.type()!=JobQueue.Type.UPLOAD_VERIFY || lease.userId()==null)throw new IllegalStateException("UPLOAD_AUTHORITY_LOST");return db.queryForMap("SELECT * FROM recording_upload WHERE user_id=? AND id=?",bytes(lease.userId()),bytes(lease.aggregateId()));}
    Map<String,Object> attemptLocked(JobQueue.Lease lease){return db.queryForMap("SELECT * FROM recording_upload WHERE user_id=? AND id=? FOR UPDATE",bytes(lease.userId()),bytes(lease.aggregateId()));}
    void requireLease(JobQueue.Lease lease){if(db.queryForList("SELECT id FROM job WHERE id=? AND user_id=? AND aggregate_id=? AND type='UPLOAD_VERIFY' AND state='RUNNING' AND lease_token=? AND lease_until>?",bytes(lease.id()),bytes(lease.userId()),bytes(lease.aggregateId()),bytes(lease.token()),LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC)).size()!=1)throw new IllegalStateException("UPLOAD_AUTHORITY_LOST");}
    public static StorageObjectKeys.Final finalKey(UUID owner,UUID recording,String value){String prefix="recordings/"+owner+"/"+recording+"/";if(value==null || !value.startsWith(prefix) || !value.endsWith(".m4a"))throw new IllegalStateException("UPLOAD_KEY_MISMATCH");var key=new StorageObjectKeys.Final(owner,recording,UUID.fromString(value.substring(prefix.length(),value.length()-4)));if(!key.value().equals(value))throw new IllegalStateException("UPLOAD_KEY_MISMATCH");return key;}
    public static Instant instant(Object value){if(value instanceof java.sql.Timestamp t)return t.toInstant();if(value instanceof LocalDateTime t)return t.toInstant(ZoneOffset.UTC);throw new IllegalStateException("UPLOAD_TIME_INVALID");}
    static long n(Map<String,Object> r,String k){return ((Number)r.get(k)).longValue();}
}
