package com.ksh321.songrecord.api.retention;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Called under USER_SYNC after fresh selection. Never deletes a file or changes usage. */
final class ReplacementProtection {
 static Set<UUID> reconcile(JdbcTemplate db,UUID owner,UUID song,Set<UUID> previous,Set<UUID> selected,long revision){
  var changed=new HashSet<UUID>();boolean waiting=false;
  for(UUID id:selected)if(db.queryForList("SELECT recording_id FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='STORED'",bytes(owner),bytes(id)).isEmpty())waiting=true;
  // The song UUID is the stable internal policy operation scope, not a client idempotency receipt.
  var existing=db.queryForList("SELECT id,recording_id,required_selection_revision FROM cloud_hold WHERE user_id=? AND reason='PENDING_REPLACEMENT' AND related_operation_id=?",bytes(owner),bytes(song));
  var protectedIds=new HashSet<UUID>();
  for(var row:existing){UUID recording=uuid((byte[])row.get("recording_id"));
   if(!waiting || selected.contains(recording)){db.update("DELETE FROM cloud_hold WHERE id=? AND user_id=?",row.get("id"),bytes(owner));changed.add(recording);}
   else{protectedIds.add(recording);if(((Number)row.get("required_selection_revision")).longValue()!=revision){db.update("UPDATE cloud_hold SET required_selection_revision=? WHERE id=? AND user_id=?",revision,row.get("id"),bytes(owner));changed.add(recording);}}
  }
  if(waiting)for(UUID id:previous){
   if(selected.contains(id) || protectedIds.contains(id))continue;
   if(db.queryForList("SELECT recording_id FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='STORED'",bytes(owner),bytes(id)).isEmpty())continue;
   db.update("INSERT INTO cloud_hold(id,user_id,recording_id,reason,related_operation_id,required_selection_revision) VALUES(?,?,?,'PENDING_REPLACEMENT',?,?)",bytes(UUID.randomUUID()),bytes(owner),bytes(id),bytes(song),revision);changed.add(id);
  }
  return changed;
 }
}
