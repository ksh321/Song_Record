package com.ksh321.songrecord.api.recordings;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.retention.CleanupObjects;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import com.ksh321.songrecord.api.sync.AccountChanges;
import java.time.*;import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Durable pending subjects, external HEAD/DELETE, then lease-fenced atomic accounting. */
public final class PurgeWorker {
 private final JdbcTemplate db;private final JobQueue jobs;private final CleanupObjects objects;private final Clock clock;private final TransactionTemplate tx;private final JsonMapper json=new JsonMapper();
 public PurgeWorker(JdbcTemplate db,PlatformTransactionManager manager,JobQueue jobs,CleanupObjects objects,Clock clock){this.db=db;this.jobs=jobs;this.objects=objects;this.clock=clock;tx=new TransactionTemplate(manager);tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);tx.setTimeout(30);}
 public boolean runOnce(){var found=jobs.claim(JobQueue.Type.ENTITY_PURGE);if(found.isEmpty())return false;var lease=found.get();try{jobs.complete(lease,prepare(lease));}catch(Exception failure){if(failure instanceof InterruptedException)Thread.currentThread().interrupt();jobs.fail(lease,true);}return true;}
 /** Returns DB effects only after confirmed owned object absence. */
 public Runnable prepare(JobQueue.Lease lease)throws Exception{var files=inspect(lease);for(var file:files){if(!jobs.renew(lease))throw lost();inspect(lease);if(objects.existsFinal(file.key())){try{objects.deleteFinal(file.key());}catch(Exception uncertain){/* HEAD below decides, never provider text. */}if(objects.existsFinal(file.key()))throw new java.io.IOException("PURGE_OBJECT_UNCONFIRMED");}}return ()->finish(lease,files);}
 private List<File> inspect(JobQueue.Lease lease){LockOrder.requireOutsideTransaction();return tx.execute(status->{requireLease(lease);UUID owner=lease.userId();lockUser(owner);var targets=targets(lease);lockSubjects(owner,targets);var files=new ArrayList<File>();
  for(var target:targets){UUID id=parseId(target);requirePending(owner,target);if(!"RECORDING".equals(target.get("entity_type")))continue;LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+id);var rows=db.queryForList("SELECT cloud_state,object_key,generation,sha256,verified_size,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(id));
   if(rows.isEmpty() || !"DELETING".equals(rows.getFirst().get("cloud_state"))){if(!rows.isEmpty() && "STORED".equals(rows.getFirst().get("cloud_state")))throw lost();continue;}
   var row=rows.getFirst();UUID generation=uuid((byte[])row.get("generation"));var key=new StorageObjectKeys.Final(owner,id,generation);if(!key.value().equals(row.get("object_key")))throw lost();files.add(new File(key,(String)row.get("sha256"),((Number)row.get("verified_size")).longValue(),((Number)row.get("cloud_revision")).longValue()));
  }requireLease(lease);return List.copyOf(files);
 });}
 private void finish(JobQueue.Lease lease,List<File> captured){
  UUID owner=lease.userId();LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");db.queryForMap("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE");lockUser(owner);LockOrder.before(LockOrder.Rank.STORAGE_USAGE,owner+"/");db.queryForMap("SELECT user_id FROM storage_usage WHERE user_id=? FOR UPDATE",bytes(owner));requireLease(lease);var targets=targets(lease);lockSubjects(owner,targets);
  var parents=new TreeSet<UUID>(Comparator.comparing(UUID::toString));
  for(var target:targets)if("SONG".equals(target.get("entity_type")))parents.addAll(db.query("SELECT DISTINCT playlist_id FROM playlist_item WHERE user_id=? AND song_id=? AND hidden_by_batch_id=?",(rs,n)->uuid(rs.getBytes(1)),bytes(owner),bytes(parseId(target)),bytes(lease.aggregateId())));
  for(UUID parent:parents){LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/2/"+parent);db.queryForList("SELECT id FROM playlist WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(parent));}
  var events=new ArrayList<AccountChanges.Change>();
  for(var target:targets)requirePending(owner,target);
  for(var file:captured){UUID id=file.key().recording();LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+id);var row=db.queryForMap("SELECT cloud_state,object_key,generation,sha256,verified_size,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(id));
   if(!"DELETING".equals(row.get("cloud_state")) || !file.key().value().equals(row.get("object_key")) || !Arrays.equals(bytes(file.key().generation()),(byte[])row.get("generation")) || !file.hash().equals(row.get("sha256")) || file.size()!=((Number)row.get("verified_size")).longValue() || file.revision()!=((Number)row.get("cloud_revision")).longValue())throw lost();
   long next=Math.incrementExact(file.revision());ledger(owner,"RECORDING_ASSET",id,file.key().generation(),next);
   if(db.update("UPDATE storage_usage SET used_bytes=used_bytes-?,revision=revision+1,updated_at=? WHERE user_id=? AND used_bytes>=?",file.size(),stamp(),bytes(owner),file.size())!=1 || db.update("UPDATE global_storage_usage SET used_bytes=used_bytes-?,revision=revision+1,updated_at=? WHERE id=1 AND used_bytes>=?",file.size(),stamp(),file.size())!=1)throw new IllegalStateException("PURGE_ACCOUNTING_MISMATCH");
   db.update("UPDATE recording_asset SET cloud_state='NONE',blocked_reason=NULL,object_key=NULL,generation=NULL,verified_size=NULL,sha256=NULL,stored_at=NULL,cloud_revision=?,updated_at=? WHERE user_id=? AND recording_id=?",next,stamp(),bytes(owner),bytes(id));
   var wire=db.queryForObject("SELECT cloud_state,blocked_reason,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=?",(rs,n)->{var value=new LinkedHashMap<String,Object>();value.put("recording_id",id.toString());value.put("user_id",owner.toString());value.put("cloud_state","NONE");value.put("blocked_reason",null);for(String key:List.of("generation","verified_size","sha256","stored_at"))value.put(key,null);value.put("cloud_revision",next);value.put("updated_at",stamp().toInstant(ZoneOffset.UTC).toString());value.put("created_at",db.queryForObject("SELECT created_at FROM recording_asset WHERE user_id=? AND recording_id=?",java.sql.Timestamp.class,bytes(owner),bytes(id)).toLocalDateTime().toInstant(ZoneOffset.UTC).toString());return value;},bytes(owner),bytes(id));
   events.add(new AccountChanges.Change(AccountChanges.Entity.RECORDING_ASSET,id,next,AccountChanges.Operation.UPSERT,json.writeValueAsString(wire)));
  }
  events.addAll(com.ksh321.songrecord.api.playlists.PlaylistService.purgeHiddenBatch(db,owner,lease.aggregateId(),targets.stream().filter(t->"SONG".equals(t.get("entity_type"))).map(PurgeWorker::parseId).toList(),parents,clock));
  for(var target:targets){UUID id=parseId(target);String type=(String)target.get("entity_type"),table=type.equals("SONG")?"song":"recording";long revision=Math.incrementExact(((Number)target.get("revision")).longValue());
   ledger(owner,type,id,null,revision);db.update("UPDATE "+table+" SET lifecycle_state='PURGED',revision=?,updated_at=? WHERE user_id=? AND id=? AND lifecycle_state='PURGE_PENDING'",revision,stamp(),bytes(owner),bytes(id));
   if(type.equals("RECORDING"))db.update("DELETE FROM cloud_hold WHERE user_id=? AND recording_id=?",bytes(owner),bytes(id));
   events.add(tombstone(type,id,revision));
  }PurgeEvents.publish(db,owner,events,clock);
 }
 private AccountChanges.Change tombstone(String type,UUID id,long revision){return new AccountChanges.Change(AccountChanges.Entity.valueOf(type),id,revision,AccountChanges.Operation.DELETE,json.writeValueAsString(Map.of("id",id.toString(),"revision",revision,"lifecycle_state","PURGED")));}
 private void ledger(UUID owner,String type,UUID id,UUID generation,long revision){db.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,object_generation,revision,purged_at) VALUES(?,?,?,?,?,?,?)",bytes(UUID.randomUUID()),bytes(owner),type,bytes(id),generation==null?null:bytes(generation),revision,stamp());}
 private List<Map<String,Object>> targets(JobQueue.Lease lease){if(lease.type()!=JobQueue.Type.ENTITY_PURGE || lease.userId()==null)throw lost();var root=json.readTree(lease.payload());if(!"TRASH_PURGE".equals(root.path("kind").asText()) || !lease.aggregateId().toString().equals(root.path("batch_id").asText()))throw lost();var result=new ArrayList<Map<String,Object>>();for(var item:root.get("targets")){String type=item.get("entity_type").asText();UUID id=TrashPurge.parse(item.get("id").asText());long revision=item.get("revision").asLong();if(!Set.of("SONG","RECORDING").contains(type) || revision<2 || db.queryForObject("SELECT COUNT(*) FROM deletion_item WHERE user_id=? AND batch_id=? AND entity_type=? AND entity_id=?",Long.class,bytes(lease.userId()),bytes(lease.aggregateId()),type,bytes(id))!=1)throw lost();result.add(Map.of("entity_type",type,"id",id.toString(),"revision",revision));}if(result.isEmpty())throw lost();return result.stream().sorted(Comparator.comparing((Map<String,Object> m)->m.get("entity_type").equals("SONG")?0:1).thenComparing(m->(String)m.get("id"))).toList();}
 private void lockSubjects(UUID owner,List<Map<String,Object>> targets){for(var target:targets){UUID id=parseId(target);String type=(String)target.get("entity_type");LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/"+(type.equals("SONG")?0:1)+"/"+id);db.queryForList("SELECT id FROM "+(type.equals("SONG")?"song":"recording")+" WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(id));}}
 private void requirePending(UUID owner,Map<String,Object> target){String table=target.get("entity_type").equals("SONG")?"song":"recording";if(db.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE user_id=? AND id=? AND lifecycle_state='PURGE_PENDING' AND revision=?",Long.class,bytes(owner),bytes(parseId(target)),target.get("revision"))!=1)throw lost();}
 private void requireLease(JobQueue.Lease lease){if(db.queryForList("SELECT id FROM job WHERE id=? AND user_id=? AND state='RUNNING' AND lease_token=? AND lease_until>?",bytes(lease.id()),bytes(lease.userId()),bytes(lease.token()),stamp()).isEmpty())throw lost();}
 private void lockUser(UUID owner){LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());db.queryForMap("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));}
 private static UUID parseId(Map<String,Object> item){return UUID.fromString((String)item.get("id"));}
 private LocalDateTime stamp(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(java.time.temporal.ChronoUnit.MILLIS);}
 private static IllegalStateException lost(){return new IllegalStateException("PURGE_AUTHORITY_LOST");}
 private record File(StorageObjectKeys.Final key,String hash,long size,long revision){}
}
