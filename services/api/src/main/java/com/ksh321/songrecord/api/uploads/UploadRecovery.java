package com.ksh321.songrecord.api.uploads;
import com.ksh321.songrecord.api.jobs.JobQueue;
import java.time.*;import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.transaction.PlatformTransactionManager;import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Terminal upload transitions release only this attempt's reservation. Existing assets remain untouched. */
public final class UploadRecovery {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final Clock clock;
 public UploadRecovery(JdbcTemplate db,PlatformTransactionManager manager,Clock clock){this.db=db;this.tx=new TransactionTemplate(manager);tx.setIsolationLevel(org.springframework.transaction.TransactionDefinition.ISOLATION_READ_COMMITTED);this.clock=clock;}
 public String cancel(UUID owner,UUID attempt){return terminal(owner,attempt,"CANCELLED","UPLOAD_CANCELLED",null);}
 public String failed(JobQueue.Lease lease,String code){return terminal(lease.userId(),lease.aggregateId(),"FAILED",safeCode(code),lease);}
 public int expire(){int done=0;var rows=db.queryForList("SELECT user_id,id FROM recording_upload WHERE state IN ('RESERVED','UPLOADING','VERIFYING') AND expires_at<=? ORDER BY expires_at,id LIMIT 100",java.sql.Timestamp.from(clock.instant()));for(var r:rows)if("EXPIRED".equals(terminal(uuid((byte[])r.get("user_id")),uuid((byte[])r.get("id")),"EXPIRED","UPLOAD_EXPIRED",null)))done++;return done;}
 public int exhausted(){int done=0;var rows=db.queryForList("SELECT a.user_id,a.id FROM recording_upload a JOIN job j ON j.user_id=a.user_id AND j.aggregate_id=a.id AND j.type='UPLOAD_VERIFY' WHERE a.state='VERIFYING' AND j.state IN ('FAILED','CANCELLED') ORDER BY a.id LIMIT 100");for(var r:rows)if("FAILED".equals(terminal(uuid((byte[])r.get("user_id")),uuid((byte[])r.get("id")),"FAILED","UPLOAD_RETRIES_EXHAUSTED",null)))done++;return done;}
 private String terminal(UUID owner,UUID attempt,String target,String code,JobQueue.Lease lease){return tx.execute(status->{
  UploadFinalization.lock(db,owner);var rows=db.queryForList("SELECT * FROM recording_upload WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(attempt));if(rows.size()!=1)throw new IllegalStateException("UPLOAD_NOT_FOUND");var row=rows.getFirst();String current=(String)row.get("state");
  if(!Set.of("RESERVED","UPLOADING","VERIFYING").contains(current))return current;
  var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC);var live=db.queryForList("SELECT id,lease_token FROM job WHERE user_id=? AND aggregate_id=? AND type='UPLOAD_VERIFY' AND state='RUNNING' AND lease_until>?",bytes(owner),bytes(attempt),now);
  if(lease!=null && (live.size()!=1 || !Arrays.equals((byte[])live.getFirst().get("lease_token"),bytes(lease.token()))))return current;
  if(target.equals("EXPIRED") && (UploadFinalization.instant(row.get("expires_at")).isAfter(clock.instant()) || !live.isEmpty()))return current;
  long size=UploadFinalization.n(row,"expected_size");var timestamp=java.sql.Timestamp.from(clock.instant());
  if(row.get("reservation_released_at")==null){
   if(db.update("UPDATE storage_usage SET reserved_bytes=reserved_bytes-?,revision=revision+1,updated_at=? WHERE user_id=? AND reserved_bytes>=?",size,timestamp,bytes(owner),size)!=1 || db.update("UPDATE global_storage_usage SET reserved_bytes=reserved_bytes-?,revision=revision+1,updated_at=? WHERE id=1 AND reserved_bytes>=?",size,timestamp,size)!=1)throw new IllegalStateException("UPLOAD_ACCOUNTING_MISMATCH");
  }
  db.update("UPDATE recording_upload SET state=?,active_slot=NULL,reservation_released_at=COALESCE(reservation_released_at,?),error_code=?,updated_at=? WHERE user_id=? AND id=?",target,timestamp,code,timestamp,bytes(owner),bytes(attempt));
  com.ksh321.songrecord.api.retention.PinTransitions.failedLocked(db,owner,uuid((byte[])row.get("recording_id")),row.get("pin_operation_id")==null?null:uuid((byte[])row.get("pin_operation_id")),clock);
  // No job lock precedes domain locks. Old effects fail their state/token fence after this transition.
  db.update("UPDATE job SET state='CANCELLED',lease_token=NULL,claimed_at=NULL,lease_until=NULL,last_error=?,finished_at=?,updated_at=?,revision=revision+1 WHERE user_id=? AND aggregate_id=? AND type='UPLOAD_VERIFY' AND state IN ('QUEUED','RETRY_WAIT','RUNNING')",code,now,now,bytes(owner),bytes(attempt));
  return target;
 });}
 public void cleanup(com.ksh321.songrecord.api.storage.R2Storage storage)throws Exception{
  // Grace exceeds the validation and SDK bounds: never delete a generation an old worker can still write.
  var rows=db.queryForList("SELECT a.user_id,a.recording_id,a.id,a.final_key FROM recording_upload a WHERE a.state IN ('FAILED','EXPIRED','CANCELLED') AND a.updated_at<=? AND NOT EXISTS(SELECT 1 FROM job j WHERE j.user_id=a.user_id AND j.aggregate_id=a.id AND j.state='RUNNING' AND j.lease_until>?) AND NOT EXISTS(SELECT 1 FROM recording_asset x WHERE x.object_key=a.final_key) ORDER BY a.id LIMIT 100",java.sql.Timestamp.from(clock.instant().minusSeconds(120)),LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC));
  long until=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(45);for(var r:rows){if(System.nanoTime()>=until)break;UUID owner=uuid((byte[])r.get("user_id")),recording=uuid((byte[])r.get("recording_id")),attempt=uuid((byte[])r.get("id"));storage.deleteTemporary(new com.ksh321.songrecord.api.storage.StorageObjectKeys.Temporary(owner,recording,attempt));storage.deleteUncommittedFinal(UploadFinalization.finalKey(owner,recording,(String)r.get("final_key")));}
 }
 private static String safeCode(String code){return Set.of("FILE_SIZE_MISMATCH","FILE_CHECKSUM_MISMATCH","FILE_AUDIO_FORMAT","FILE_DECODE_FAILED","FILE_VALIDATION_TIMEOUT","UPLOAD_TOO_LARGE","UPLOAD_AUTHORITY_LOST","NOT_CLOUD_TARGET","UPLOAD_POLICY_CHANGED","FILE_SPEC_MISMATCH").contains(code)?code:"FILE_INVALID";}
}
