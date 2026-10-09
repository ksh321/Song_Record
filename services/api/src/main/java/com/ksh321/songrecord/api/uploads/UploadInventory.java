package com.ksh321.songrecord.api.uploads;
import java.time.*;import java.util.*;import java.security.MessageDigest;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.transaction.PlatformTransactionManager;import org.springframework.transaction.support.TransactionTemplate;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;import com.ksh321.songrecord.api.locking.LockOrder;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Full object observation and conservative guards. Never delete a referenced final generation or repair counters blindly. */
public final class UploadInventory {
 public static final long TEMP_LIMIT=512L*1024*1024;private final JdbcTemplate db;private final TransactionTemplate tx;private final UploadObjectInventory objects;private final Clock clock;
 public record Result(long observed,long removed,long protectedObjects,long issues){}
 public UploadInventory(JdbcTemplate db,PlatformTransactionManager manager,UploadObjectInventory objects,Clock clock){this.db=db;tx=new TransactionTemplate(manager);this.objects=objects;this.clock=clock;}
 public Result temporary()throws Exception{
  long[] stats=new long[4];try{objects.temporaryObjects(entry->{stats[0]=Math.addExact(stats[0],entry.size());var key=temporaryKey(entry.key());if(key.isEmpty())return;
   var rows=db.queryForList("SELECT state,updated_at FROM recording_upload WHERE user_id=? AND recording_id=? AND id=? AND temp_key=?",bytes(key.get().owner()),bytes(key.get().recording()),bytes(key.get().attempt()),entry.key());
   if(!rows.isEmpty() && Set.of("RESERVED","UPLOADING","VERIFYING").contains(rows.getFirst().get("state"))){stats[2]++;return;}
   if(!db.queryForList("SELECT id FROM job WHERE user_id=? AND aggregate_id=? AND type='UPLOAD_VERIFY' AND state='RUNNING' AND lease_until>?",bytes(key.get().owner()),bytes(key.get().attempt()),LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC)).isEmpty()){stats[2]++;return;}
   Instant safeAfter=rows.isEmpty()?entry.modified().plusSeconds(600):UploadFinalization.instant(rows.getFirst().get("updated_at")).plusSeconds(600);
   if(!safeAfter.isAfter(clock.instant())){objects.deleteTemporary(key.get());stats[1]++;}
  });setTemporary(stats[0]);return new Result(stats[0],stats[1],stats[2],0);}
  catch(Exception e){setTemporary(Math.max(TEMP_LIMIT,stats[0]));throw e;}
 }
 public Result daily()throws Exception{
  long[] stats=new long[4];try{
   objects.finalObjects(entry->{stats[0]=Math.addExact(stats[0],entry.size());var key=finalKey(entry.key());if(key.isEmpty()){stats[3]++;return;}
    var linked=db.queryForList("SELECT recording_id FROM recording_asset WHERE object_key=? AND cloud_state IN ('STORED','DELETING')",entry.key());
    if(!linked.isEmpty()){stats[2]++;return;}
    var attempts=db.queryForList("SELECT state,updated_at FROM recording_upload WHERE final_key=?",entry.key());
    if(!attempts.isEmpty() && Set.of("RESERVED","UPLOADING","VERIFYING").contains(attempts.getFirst().get("state"))){stats[2]++;return;}
    Instant safe=attempts.isEmpty()?entry.modified().plusSeconds(120):UploadFinalization.instant(attempts.getFirst().get("updated_at")).plusSeconds(120);
    if(safe.isAfter(clock.instant())){stats[2]++;return;}
    // A terminal/missing attempt cannot create a new reference; generations are never reused.
    if(db.queryForList("SELECT recording_id FROM recording_asset WHERE object_key=?",entry.key()).isEmpty()){objects.deleteUncommittedFinal(key.get());stats[1]++;}
   });
   byte[] cursor=new byte[16];long deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(120);
   while(true){var rows=db.queryForList("SELECT user_id,recording_id,object_key,generation,verified_size,sha256 FROM recording_asset WHERE recording_id>? AND cloud_state IN ('STORED','DELETING') ORDER BY recording_id LIMIT 100",cursor);if(rows.isEmpty())break;
    for(var row:rows){if(System.nanoTime()>=deadline)throw new java.io.IOException("INVENTORY_TIMEOUT");cursor=(byte[])row.get("recording_id");var key=finalKey((String)row.get("object_key"));boolean valid=key.isPresent() && key.get().owner().equals(uuid((byte[])row.get("user_id"))) && key.get().recording().equals(uuid(cursor)) && key.get().generation().equals(uuid((byte[])row.get("generation")));
     if(valid){var data=objects.readFinal(key.get());if(data.isEmpty())valid=false;else {var buffer=data.get().asReadOnlyBuffer();if(buffer.remaining()!=UploadFinalization.n(row,"verified_size"))valid=false;else{var bytes=new byte[buffer.remaining()];buffer.get(bytes);valid=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)).equals(row.get("sha256"));}}}
     if(!valid && !db.queryForList("SELECT recording_id FROM recording_asset WHERE recording_id=? AND object_key=? AND generation=? AND cloud_state IN ('STORED','DELETING')",cursor,row.get("object_key"),row.get("generation")).isEmpty())stats[3]++;
    }
   }
   tx.executeWithoutResult(s->{lockGlobal();long bad=db.queryForObject("SELECT COUNT(*) FROM storage_usage u WHERE u.used_bytes<>COALESCE((SELECT SUM(a.verified_size) FROM recording_asset a WHERE a.user_id=u.user_id AND a.cloud_state IN ('STORED','DELETING')),0) OR u.reserved_bytes<>COALESCE((SELECT SUM(a.expected_size) FROM recording_upload a WHERE a.user_id=u.user_id AND a.state IN ('RESERVED','UPLOADING','VERIFYING')),0)",Long.class);
    var row=db.queryForMap("SELECT used_bytes,reserved_bytes FROM global_storage_usage WHERE id=1");long used=db.queryForObject("SELECT COALESCE(SUM(used_bytes),0) FROM storage_usage",Long.class),reserved=db.queryForObject("SELECT COALESCE(SUM(reserved_bytes),0) FROM storage_usage",Long.class);if(UploadFinalization.n(row,"used_bytes")!=used || UploadFinalization.n(row,"reserved_bytes")!=reserved)bad++;
    bad+=db.queryForObject("SELECT COUNT(*) FROM recording_upload a WHERE a.state='VERIFYING' AND NOT EXISTS(SELECT 1 FROM job j WHERE j.user_id=a.user_id AND j.aggregate_id=a.id AND j.type='UPLOAD_VERIFY')",Long.class);stats[3]=Math.addExact(stats[3],bad);db.update("UPDATE global_storage_usage SET final_observed_bytes=?,reconciliation_issue_count=?,reconciliation_locked=?,reconciliation_at=?,revision=revision+1 WHERE id=1",stats[0],stats[3],stats[3]>0,java.sql.Timestamp.from(clock.instant()));});return new Result(stats[0],stats[1],stats[2],stats[3]);
  }catch(Exception e){tx.executeWithoutResult(s->{lockGlobal();db.update("UPDATE global_storage_usage SET reconciliation_locked=TRUE,reconciliation_issue_count=GREATEST(reconciliation_issue_count,1),revision=revision+1 WHERE id=1");});throw e;}
 }
 private void setTemporary(long total){tx.executeWithoutResult(s->{lockGlobal();db.update("UPDATE global_storage_usage SET temp_observed_bytes=?,revision=revision+1,updated_at=? WHERE id=1",total,java.sql.Timestamp.from(clock.instant()));});}
 private void lockGlobal(){LockOrder.before(LockOrder.Rank.GLOBAL_STORAGE,"1");db.queryForMap("SELECT id FROM global_storage_usage WHERE id=1 FOR UPDATE");}
 public static Optional<StorageObjectKeys.Temporary> temporaryKey(String value){try{var p=value.split("/",-1);if(p.length!=4 || !p[0].equals("temporary"))return Optional.empty();var key=new StorageObjectKeys.Temporary(UUID.fromString(p[1]),UUID.fromString(p[2]),UUID.fromString(p[3]));return key.value().equals(value)?Optional.of(key):Optional.empty();}catch(RuntimeException e){return Optional.empty();}}
 public static Optional<StorageObjectKeys.Final> finalKey(String value){try{var p=value.split("/",-1);if(p.length!=4 || !p[0].equals("recordings"))return Optional.empty();var key=UploadFinalization.finalKey(UUID.fromString(p[1]),UUID.fromString(p[2]),value);return Optional.of(key);}catch(RuntimeException e){return Optional.empty();}}
}
