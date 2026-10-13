package com.ksh321.songrecord.api.account;
import java.util.*;
import java.time.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ConnectionCallback;
import com.ksh321.songrecord.api.locking.LockOrder;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Reviewed owner tables only; FK metadata orders deletions without disabling constraints. */
public final class DeletionDatabase {
 private static final Set<String> PERSONAL=Set.of("account_deletion_challenge","auth_identity","auth_session","change_log","cloud_cleanup","cloud_hold","condition_definition","deletion_batch_work","deletion_item","export_session","mutation_receipt","pin_slot","playlist_item","recording_asset","recording_condition_history","recording_file_spec","recording_query_key","recording_tag","recording_time_correction","recording_upload","song_cloud_selection","song_query_key","song_source","storage_request_body","storage_request_operation","storage_usage","upload_approval_daily","upload_url_issue","deletion_batch","playlist","recording","snapshot_header","storage_request_ledger","tag","user_entitlement","user_sync_state","device","song");
 private static final Set<String> CONTROL=Set.of("deletion_ledger","job","account_deletion_status");
 private final JdbcTemplate db;
 public DeletionDatabase(JdbcTemplate db){this.db=db;}
 public List<String> order(){return db.execute((ConnectionCallback<List<String>>) c->{
  var meta=c.getMetaData();var catalog=c.getCatalog();var schema=c.getSchema();var dependencies=new TreeMap<String,Set<String>>();
  try(var tables=meta.getTables(catalog,schema,"%",new String[]{"TABLE","BASE TABLE"})){while(tables.next()){
   var actual=tables.getString("TABLE_NAME");var name=actual.toLowerCase(Locale.ROOT);boolean owned=false;
   try(var columns=meta.getColumns(catalog,schema,actual,"%")){while(columns.next())if("user_id".equalsIgnoreCase(columns.getString("COLUMN_NAME")))owned=true;}
   if(!owned||CONTROL.contains(name))continue;if(!PERSONAL.contains(name))throw new IllegalStateException("UNREVIEWED_ACCOUNT_TABLE");
   var parents=new HashSet<String>();try(var keys=meta.getImportedKeys(catalog,schema,actual)){while(keys.next())parents.add(keys.getString("PKTABLE_NAME").toLowerCase(Locale.ROOT));}dependencies.put(name,parents);
  }}
  if(dependencies.containsKey("song"))dependencies.get("song").remove("recording");
  var result=new ArrayList<String>();while(!dependencies.isEmpty()){
   var leaves=dependencies.keySet().stream().filter(k->dependencies.entrySet().stream().noneMatch(e->!e.getKey().equals(k)&&e.getValue().contains(k))).toList();
   if(leaves.isEmpty())throw new IllegalStateException("ACCOUNT_FOREIGN_KEY_CYCLE_UNREVIEWED");for(var leaf:leaves){result.add(leaf);dependencies.remove(leaf);}
  }return List.copyOf(result);
 });}
 public void purge(UUID owner,UUID currentJob,LocalDateTime now){
  LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");db.queryForMap("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE");
  db.queryForMap("SELECT id FROM snapshot_capacity WHERE id=1 FOR UPDATE");
  LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));
  var users=db.queryForList("SELECT status FROM app_user WHERE id=? FOR UPDATE",bytes(owner));if(users.size()!=1||!"DELETING".equals(users.getFirst().get("status")))throw new IllegalStateException("DELETION_OWNER_AUTHORITY_LOST");
  var order=order();var usage=db.queryForMap("SELECT used_bytes,reserved_bytes FROM storage_usage WHERE user_id=? FOR UPDATE",bytes(owner));
  long used=((Number)usage.get("used_bytes")).longValue(),reserved=((Number)usage.get("reserved_bytes")).longValue();
  if(db.update("UPDATE global_storage_usage SET used_bytes=used_bytes-?,reserved_bytes=reserved_bytes-?,revision=revision+1,updated_at=? WHERE id=1 AND used_bytes>=? AND reserved_bytes>=?",used,reserved,now,used,reserved)!=1)throw new IllegalStateException("ACCOUNT_STORAGE_ACCOUNTING_UNCONFIRMED");
  db.update("UPDATE song SET representative_recording_id=NULL,revision=revision+1,updated_at=GREATEST(updated_at,?) WHERE user_id=? AND representative_recording_id IS NOT NULL",now,bytes(owner));
  // File-spec deletion is already permitted only after SAVED recordings are PURGED.
  db.update("UPDATE recording SET lifecycle_state='PURGED',deleted_at=COALESCE(deleted_at,?),revision=revision+1,updated_at=GREATEST(updated_at,?) WHERE user_id=? AND lifecycle_state<>'PURGED'",now,now,bytes(owner));
  // V7's existing deletion trigger refunds snapshot capacity exactly once.
  db.update("UPDATE snapshot_header SET status='EXPIRED',active_slot=NULL WHERE user_id=? AND status='READY'",bytes(owner));
  db.update("UPDATE snapshot_header SET status='FAILED',active_slot=NULL,lease_until=NULL WHERE user_id=? AND status='BUILDING'",bytes(owner));
  for(var table:order)if(!table.equals("recording_condition_history"))db.update("DELETE FROM "+table+" WHERE user_id=?",bytes(owner));
  // Append-only condition history is removed by its owning-recording FK cascade.
  db.update("DELETE FROM job WHERE user_id=? AND id<>?",bytes(owner),bytes(currentJob));
  db.update("UPDATE account_deletion_status SET user_id=NULL,session_id=NULL,challenge_id=NULL,operation_id=NULL,request_hash=NULL WHERE user_id=?",bytes(owner));
  if(db.update("DELETE FROM app_user WHERE id=? AND status='DELETING'",bytes(owner))!=1)throw new IllegalStateException("ACCOUNT_DELETE_UNCONFIRMED");
  for(var table:order)if(db.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE user_id=?",Long.class,bytes(owner))!=0)throw new IllegalStateException("ACCOUNT_ROWS_REMAIN");
 }
 public boolean purged(UUID owner){if(!db.queryForList("SELECT id FROM app_user WHERE id=?",bytes(owner)).isEmpty())return false;for(var table:order())if(db.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE user_id=?",Long.class,bytes(owner))!=0)return false;return true;}
}
