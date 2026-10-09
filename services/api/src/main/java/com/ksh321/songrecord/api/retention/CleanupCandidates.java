package com.ksh321.songrecord.api.retention;

import java.util.*;
import org.springframework.context.annotation.*;
import org.springframework.stereotype.Component;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import com.ksh321.songrecord.api.locking.LockOrder;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Recomputes reasons only. A candidate is never permission to delete a server object. */
@Component @Profile("!bootstrap")
public final class CleanupCandidates {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final RetentionCandidates candidates;
 private UUID cursorOwner,cursorRecording;
 public CleanupCandidates(JdbcTemplate db,PlatformTransactionManager manager){this.db=db;candidates=new RetentionCandidates(db);tx=new TransactionTemplate(manager);tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);}
 public boolean recalculate(UUID owner,UUID recording){
  Objects.requireNonNull(owner);Objects.requireNonNull(recording);LockOrder.requireOutsideTransaction();
  return Boolean.TRUE.equals(tx.execute(s->{
   LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());
   if(db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner)).isEmpty() || db.queryForList("SELECT id FROM app_user WHERE id=? AND status='ACTIVE'",bytes(owner)).isEmpty())return false;
   var records=db.queryForList("SELECT song_id,lifecycle_state,metadata_state FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(recording));if(records.isEmpty())return false;
   var metadata=records.getFirst();boolean automatic=false;
   if(metadata.get("song_id")!=null){UUID song=uuid((byte[])metadata.get("song_id"));var songs=db.queryForList("SELECT representative_recording_id FROM song WHERE user_id=? AND id=? AND lifecycle_state='ACTIVE'",bytes(owner),bytes(song));
    if(!songs.isEmpty()){byte[] representative=(byte[])songs.getFirst().get("representative_recording_id");automatic=RetentionRoles.calculate(candidates.forSong(owner,song),representative==null?null:uuid(representative)).recordingIds().contains(recording);}}
   boolean pinned=!db.queryForList("SELECT slot_no FROM pin_slot WHERE user_id=? AND (current_recording_id=? OR pending_recording_id=?)",bytes(owner),bytes(recording),bytes(recording)).isEmpty();
   LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+recording);
   var assets=db.queryForList("SELECT cloud_state,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(recording));if(assets.isEmpty() || !"STORED".equals(assets.getFirst().get("cloud_state")))return false;
   boolean changed=false;
   // Disconnected server copies retain a standing orphan reason without occupying a pin slot.
   if(metadata.get("song_id")==null)changed=ensure(owner,recording,"ORPHAN_KEEP");
   else if(automatic || pinned)changed=db.update("DELETE FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason='ORPHAN_KEEP'",bytes(owner),bytes(recording))>0;
   // Without a new mandatory role the standing orphan reason survives until valid cleanup confirmation.
   boolean protectedCopy=automatic || pinned || !db.queryForList("SELECT id FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason<>'WAITING_LOCAL_CONFIRM'",bytes(owner),bytes(recording)).isEmpty();
   if(protectedCopy)changed=db.update("DELETE FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason='WAITING_LOCAL_CONFIRM'",bytes(owner),bytes(recording))>0 || changed;
   else changed=ensure(owner,recording,"WAITING_LOCAL_CONFIRM") || changed;
   if(changed)RetentionAssetVersions.bumpLocked(db,owner,recording,assets);
   return !protectedCopy;
  }));
 }
 private boolean ensure(UUID owner,UUID recording,String reason){
  if(!db.queryForList("SELECT id FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason=? AND related_operation_id IS NULL",bytes(owner),bytes(recording),reason).isEmpty())return false;
  db.update("INSERT INTO cloud_hold(id,user_id,recording_id,reason) VALUES(?,?,?,?)",bytes(UUID.randomUUID()),bytes(owner),bytes(recording),reason);return true;
 }
 /** Cursor rotation prevents a protected first page from starving later assets. */
 public synchronized void refresh(){
  LockOrder.requireOutsideTransaction();String cursor=cursorOwner==null?"":" AND (user_id>? OR (user_id=? AND recording_id>?))";
  Object[] args=cursorOwner==null?new Object[0]:new Object[]{bytes(cursorOwner),bytes(cursorOwner),bytes(cursorRecording)};
  var rows=db.queryForList("SELECT user_id,recording_id FROM recording_asset WHERE cloud_state='STORED'"+cursor+" ORDER BY user_id,recording_id LIMIT 100",args);
  if(rows.isEmpty()){cursorOwner=null;cursorRecording=null;return;}
  for(var row:rows){UUID owner=uuid((byte[])row.get("user_id")),recording=uuid((byte[])row.get("recording_id"));recalculate(owner,recording);cursorOwner=owner;cursorRecording=recording;}
 }
}
