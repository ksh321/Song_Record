package com.ksh321.songrecord.api.recordings;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;import java.util.*;
import org.springframework.http.HttpStatus;import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Persist fences and durable work before any network deletion. */
public final class TrashPurge {
 private final JdbcTemplate db;private final AccountAccess access;private final IdempotentMutations mutations;private final AccountChanges changes;private final JobQueue jobs;private final RecordingEditing editing;private final Clock clock;private final JsonMapper json=new JsonMapper();
 public TrashPurge(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,AccountChanges changes,JobQueue jobs,RecordingEditing editing,Clock clock){this.db=db;this.access=access;this.mutations=mutations;this.changes=changes;this.jobs=jobs;this.editing=editing;this.clock=clock;}
 public IdempotentMutations.Reply purge(String auth,String device,String operation,String rawBatch,String body){
  var account=access.authenticate(auth,device);UUID batch=parse(rawBatch);var root=json.readTree(CanonicalRequest.canonical(body));
  if(!root.isObject() || !root.has("base_revision") || !root.get("base_revision").isIntegralNumber() || !root.get("base_revision").canConvertToLong() || root.get("base_revision").asLong()<1 || root.size()!=(root.has("item_ids")?2:1))throw invalid("VALIDATION_FAILED");
  Set<UUID> selection=null;if(root.has("item_ids")){selection=new HashSet<>();if(!root.get("item_ids").isArray() || root.get("item_ids").isEmpty() || root.get("item_ids").size()>100)throw invalid("VALIDATION_FAILED");for(var id:root.get("item_ids"))if(!id.isTextual() || !selection.add(parse(id.asText())))throw invalid("VALIDATION_FAILED");}
  Set<UUID> selected=selection;
  return mutations.execute(account,operation,"POST","/v1/trash/"+batch+"/purge",body,()->changes.write(account,()->{
   UUID owner=account.principal().userId();var prepared=prepare(owner,batch,selected,root.get("base_revision").asLong());
   UUID job=jobs.enqueue(account,JobQueue.Type.ENTITY_PURGE,batch,parse(operation),prepared.payload());
   return new AccountChanges.Batch<>(new IdempotentMutations.Reply(202,json.writeValueAsString(Map.of("batch_id",batch.toString(),"revision",prepared.version(),"job_id",job.toString(),"state","PURGE_PENDING"))),prepared.events());
  }).value());
 }
 record Prepared(String payload,long version,List<AccountChanges.Change> events){}
 /** Server-owned expiry discovery; never accept an owner from a public request. */
 public int expire(){
  var candidates=db.queryForList("SELECT b.user_id,b.id,COALESCE(w.revision,1) AS revision FROM deletion_batch b JOIN app_user u ON u.id=b.user_id AND u.status='ACTIVE' LEFT JOIN deletion_batch_work w ON w.user_id=b.user_id AND w.batch_id=b.id WHERE b.purge_after<=? AND EXISTS(SELECT 1 FROM deletion_item i LEFT JOIN song s ON i.entity_type='SONG' AND s.user_id=i.user_id AND s.id=i.entity_id LEFT JOIN recording r ON i.entity_type='RECORDING' AND r.user_id=i.user_id AND r.id=i.entity_id WHERE i.user_id=b.user_id AND i.batch_id=b.id AND ((s.lifecycle_state='TRASHED' AND s.deleted_at=b.deleted_at) OR (r.lifecycle_state='TRASHED' AND r.deleted_at=b.deleted_at))) ORDER BY b.purge_after,b.id LIMIT 20",stamp());
  var tx=new TransactionTemplate(new DataSourceTransactionManager(db.getDataSource()));int done=0;
  for(var row:candidates){UUID owner=uuid((byte[])row.get("user_id")),batch=uuid((byte[])row.get("id"));long version=((Number)row.get("revision")).longValue();
   try{tx.executeWithoutResult(status->{LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());db.queryForMap("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));if(db.queryForList("SELECT id FROM app_user WHERE id=? AND status='ACTIVE'",bytes(owner)).isEmpty())throw conflict("ACCOUNT_NOT_ACTIVE");var prepared=prepare(owner,batch,null,version);UUID operation=UUID.nameUUIDFromBytes(("expiry/"+batch+"/"+version).getBytes(java.nio.charset.StandardCharsets.UTF_8));jobs.enqueueOwnedMaintenance(owner,JobQueue.Type.ENTITY_PURGE,batch,operation,prepared.payload());PurgeEvents.publish(db,owner,prepared.events(),clock);});done++;}
   catch(ApiException concurrent){if(!Set.of("REVISION_CONFLICT","TRASH_ITEM_NOT_AVAILABLE","FILE_CLEANUP_IN_PROGRESS","ACCOUNT_NOT_ACTIVE").contains(concurrent.code()))throw concurrent;}
  }return done;
 }
 private Prepared prepare(UUID owner,UUID batch,Set<UUID> selection,long base){
  var rows=db.queryForList("SELECT deleted_at FROM deletion_batch WHERE user_id=? AND id=?",bytes(owner),bytes(batch));if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","휴지통 묶음을 확인해 주세요.",false,Map.of());
  var deleted=TrashRestoration.time(rows.getFirst().get("deleted_at"));
  db.update("INSERT INTO deletion_batch_work(user_id,batch_id,revision) SELECT ?,?,1 WHERE NOT EXISTS(SELECT 1 FROM deletion_batch_work WHERE user_id=? AND batch_id=?)",bytes(owner),bytes(batch),bytes(owner),bytes(batch));
  long version=db.queryForObject("SELECT revision FROM deletion_batch_work WHERE user_id=? AND batch_id=? FOR UPDATE",Long.class,bytes(owner),bytes(batch));if(version!=base || version==Long.MAX_VALUE)throw conflict("REVISION_CONFLICT");
  var members=db.queryForList("SELECT entity_type,entity_id FROM deletion_item WHERE user_id=? AND batch_id=? AND entity_type IN ('SONG','RECORDING') ORDER BY CASE WHEN entity_type='SONG' THEN 0 ELSE 1 END,entity_id",bytes(owner),bytes(batch));
  if(selection!=null)for(UUID id:selection)if(members.stream().filter(m->Arrays.equals((byte[])m.get("entity_id"),bytes(id))).count()!=1)throw invalid("INVALID_TRASH_ITEM");
  var targets=new ArrayList<Map<String,Object>>();var events=new ArrayList<AccountChanges.Change>();var assets=new ArrayList<UUID>();
  for(var member:members){UUID id=uuid((byte[])member.get("entity_id"));if(selection!=null && !selection.contains(id))continue;String type=(String)member.get("entity_type"),table=type.equals("SONG")?"song":"recording";
   LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/"+(type.equals("SONG")?0:1)+"/"+id);
   var current=db.queryForList("SELECT lifecycle_state,deleted_at,revision FROM "+table+" WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(id));
   if(current.isEmpty() || !"TRASHED".equals(current.getFirst().get("lifecycle_state")) || !deleted.equals(TrashRestoration.time(current.getFirst().get("deleted_at")))){if(selection!=null)throw conflict("TRASH_ITEM_NOT_AVAILABLE");continue;}
   long next=Math.incrementExact(((Number)current.getFirst().get("revision")).longValue());db.update("UPDATE "+table+" SET lifecycle_state='PURGE_PENDING',revision=?,updated_at=? WHERE user_id=? AND id=?",next,stamp(),bytes(owner),bytes(id));
   targets.add(Map.of("entity_type",type,"id",id.toString(),"revision",next));
   var wire=type.equals("SONG")?songSnapshot(owner,id):recordSnapshot(owner,id);
   events.add(new AccountChanges.Change(AccountChanges.Entity.valueOf(type),id,next,AccountChanges.Operation.UPSERT,json.writeValueAsString(wire)));
   if(type.equals("RECORDING"))assets.add(id);
  }
  if(targets.isEmpty())throw conflict("TRASH_ITEM_NOT_AVAILABLE");
  for(UUID id:assets.stream().sorted(Comparator.comparing(UUID::toString)).toList()){
   LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+id);var row=db.queryForList("SELECT cloud_state,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? FOR UPDATE",bytes(owner),bytes(id));
   if(row.isEmpty())continue;if("DELETING".equals(row.getFirst().get("cloud_state")))throw conflict("FILE_CLEANUP_IN_PROGRESS");long next=Math.incrementExact(((Number)row.getFirst().get("cloud_revision")).longValue());
   db.update("UPDATE recording_asset SET cloud_state=CASE WHEN cloud_state='STORED' THEN 'DELETING' ELSE cloud_state END,cloud_revision=?,updated_at=? WHERE user_id=? AND recording_id=?",next,stamp(),bytes(owner),bytes(id));
  }
  db.update("UPDATE deletion_batch_work SET revision=revision+1,updated_at=? WHERE user_id=? AND batch_id=?",stamp(),bytes(owner),bytes(batch));
  return new Prepared(json.writeValueAsString(Map.of("kind","TRASH_PURGE","batch_id",batch.toString(),"targets",targets)),version+1,events);
 }
 private Map<String,Object> songSnapshot(UUID owner,UUID id){var current=com.ksh321.songrecord.api.revision.RevisionChanges.readSnapshot(db,com.ksh321.songrecord.api.revision.RevisionChanges.Resource.SONG,owner,id);var value=new LinkedHashMap<>(com.ksh321.songrecord.api.songs.SongEditing.wire(current));value.put("deleted_at",current.get("deleted_at"));return value;}
 private Map<String,Object> recordSnapshot(UUID owner,UUID id){var value=editing.snapshot(owner,id);value.put("deleted_at",com.ksh321.songrecord.api.revision.RevisionChanges.readSnapshot(db,com.ksh321.songrecord.api.revision.RevisionChanges.Resource.RECORDING,owner,id).get("deleted_at"));return value;}
 private LocalDateTime stamp(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(java.time.temporal.ChronoUnit.MILLIS);}
 static UUID parse(String value){try{var id=UUID.fromString(value);if(!id.toString().equals(value))throw new IllegalArgumentException();return id;}catch(RuntimeException e){throw invalid("VALIDATION_FAILED");}}
 static ApiException invalid(String code){return new ApiException(HttpStatus.BAD_REQUEST,code,"삭제할 휴지통 항목을 확인해 주세요.",false,Map.of());}
 static ApiException conflict(String code){return new ApiException(HttpStatus.CONFLICT,code,"최신 휴지통 상태를 확인해 주세요.",false,Map.of());}
}
