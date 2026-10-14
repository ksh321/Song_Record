package com.ksh321.songrecord.api.operations;

import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** Separate backup process acknowledges a verified remote fence before destructive I/O. */
public final class BackupDeletionFence {
 public static final class Awaiting extends RuntimeException {public Awaiting(){super("BACKUP_DELETION_FENCE_PENDING");}}
 public static final BackupDeletionFence NONE=new BackupDeletionFence(null,Clock.systemUTC(),false);
 private final JdbcTemplate db;private final Clock clock;private final boolean required;
 public BackupDeletionFence(JdbcTemplate db,Clock clock,boolean required){this.db=db;this.clock=clock;this.required=required;}
 public void generation(StorageObjectKeys.Final key){authorize(key.owner(),"RECORDING_ASSET",key.recording(),key.generation());}
 public void user(UUID owner,Instant accepted){
  if(accepted==null||accepted.isAfter(clock.instant()))throw new IllegalArgumentException("BACKUP_FENCE_TIME_INVALID");
  try{authorize(owner,"USER",owner,null);}finally{if(required)db.update("UPDATE operational_backup_fence SET requested_at=LEAST(requested_at,?) WHERE user_id=? AND entity_type='USER' AND entity_id=?",java.sql.Timestamp.from(accepted),bytes(owner),bytes(owner));}
 }
 public void authorize(UUID owner,String type,UUID entity,UUID generation){
  if(!required)return;
  if(owner==null||entity==null||!Set.of("USER","SONG","RECORDING","RECORDING_ASSET").contains(type)||type.equals("RECORDING_ASSET")!=(generation!=null)||type.equals("USER")&&!owner.equals(entity))throw new IllegalArgumentException("BACKUP_FENCE_SUBJECT_INVALID");
  var rows=db.queryForList("SELECT state,revision,backup_ack_revision FROM operational_backup_fence WHERE user_id=? AND entity_type=? AND entity_id=? AND generation_key=?",bytes(owner),type,bytes(entity),generation==null?new byte[16]:bytes(generation));
  if(rows.isEmpty()){
   try{db.update("INSERT INTO operational_backup_fence(id,user_id,entity_type,entity_id,object_generation,requested_at,updated_at) VALUES(?,?,?,?,?,?,?)",bytes(UUID.randomUUID()),bytes(owner),type,bytes(entity),generation==null?null:bytes(generation),now(),now());}
   catch(org.springframework.dao.DuplicateKeyException concurrent){/* A single immutable subject row wins; read on the next bounded attempt. */}
   throw new Awaiting();
  }
  var row=rows.getFirst();
  if("CANCELLED".equals(row.get("state"))){db.update("UPDATE operational_backup_fence SET state='REQUESTED',revision=revision+1,updated_at=? WHERE user_id=? AND entity_type=? AND entity_id=? AND generation_key=? AND state='CANCELLED'",now(),bytes(owner),type,bytes(entity),generation==null?new byte[16]:bytes(generation));throw new Awaiting();}
  if(((Number)row.get("backup_ack_revision")).longValue()!=((Number)row.get("revision")).longValue())throw new Awaiting();
 }
 public void cancel(StorageObjectKeys.Final key){if(required)db.update("UPDATE operational_backup_fence SET state='CANCELLED',revision=revision+1,updated_at=? WHERE user_id=? AND entity_type='RECORDING_ASSET' AND entity_id=? AND generation_key=? AND state='REQUESTED'",now(),bytes(key.owner()),bytes(key.recording()),bytes(key.generation()));}
 public void committed(StorageObjectKeys.Final key){if(required)db.update("UPDATE operational_backup_fence SET state='COMMITTED',revision=revision+1,updated_at=? WHERE user_id=? AND entity_type='RECORDING_ASSET' AND entity_id=? AND generation_key=? AND state='REQUESTED'",now(),bytes(key.owner()),bytes(key.recording()),bytes(key.generation()));}
 public boolean ownerBackupsAbsent(UUID owner){if(!required)return false;return !db.queryForList("SELECT id FROM operational_backup_fence WHERE user_id=? AND entity_type='USER' AND entity_id=? AND backup_ack_revision=revision AND backup_absent_at IS NOT NULL",bytes(owner),bytes(owner)).isEmpty();}
 private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(java.time.temporal.ChronoUnit.MILLIS);}
}
