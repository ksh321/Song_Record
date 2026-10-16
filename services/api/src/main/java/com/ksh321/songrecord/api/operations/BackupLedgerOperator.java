package com.ksh321.songrecord.api.operations;
import java.nio.file.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Private validation-only metadata outbox. No public endpoint, tokens or content in output. */
public final class BackupLedgerOperator {
 public static void main(String[] args){try{
  if(args.length!=1||!Set.of("snapshot","ack","authorize-fixture","retire").contains(args[0]))throw new IllegalArgumentException();
  var source=PrivateOperationsDataSource.open();
  var db=new JdbcTemplate(source);var json=new tools.jackson.databind.json.JsonMapper();
  if(args[0].equals("snapshot")){
   var entries=new ArrayList<Map<String,Object>>();var pending=new ArrayList<Map<String,Object>>();
   for(var row:db.queryForList("SELECT id,user_id,entity_type,entity_id,object_generation,state,revision,backup_ack_revision,updated_at,backup_absent_at FROM operational_backup_fence ORDER BY id LIMIT 100001")){
    var item=project(row,"updated_at");item.put("state",row.get("state"));item.put("origin","fence");entries.add(item);
    if(!row.get("revision").equals(row.get("backup_ack_revision"))||"USER".equals(row.get("entity_type"))&&row.get("backup_absent_at")==null)pending.add(Map.of("id",uuid((byte[])row.get("id")).toString(),"revision",row.get("revision"),"owner",item.get("owner"),"type",item.get("type"),"entity",item.get("entity"),"generation",item.getOrDefault("generation",""),"needs_ack",!row.get("revision").equals(row.get("backup_ack_revision"))));
   }
   for(var row:db.queryForList("SELECT user_id,entity_type,entity_id,object_generation,revision,purged_at FROM deletion_ledger ORDER BY id LIMIT 100001")){var item=project(row,"purged_at");item.put("state","COMMITTED");item.put("origin","ledger");entries.add(item);}
   if(entries.size()>100000)throw new IllegalStateException();
   System.out.println(json.writeValueAsString(Map.of("entries",entries,"pending",pending)));
  }else if(args[0].equals("retire")){
   var rows=json.readTree(System.in.readNBytes(65537));if(!rows.isArray()||rows.size()>1000)throw new IllegalArgumentException();
   for(var row:rows){var owner=UUID.fromString(row.asText());
    if(db.queryForObject("SELECT COUNT(*) FROM app_user WHERE id=?",Long.class,bytes(owner))!=0||db.queryForObject("SELECT COUNT(*) FROM deletion_ledger WHERE user_id=?",Long.class,bytes(owner))!=0||db.queryForObject("SELECT COUNT(*) FROM account_deletion_work WHERE owner_id=?",Long.class,bytes(owner))!=0)throw new IllegalStateException();
    long existing=db.queryForObject("SELECT COUNT(*) FROM operational_backup_fence WHERE user_id=? AND entity_type='USER'",Long.class,bytes(owner));
    if(existing>0&&db.queryForObject("SELECT COUNT(*) FROM operational_backup_fence WHERE user_id=? AND entity_type='USER' AND backup_absent_at IS NOT NULL AND requested_at<=UTC_TIMESTAMP(3)-INTERVAL 30 DAY",Long.class,bytes(owner))!=1)throw new IllegalStateException();
    db.update("DELETE FROM operational_backup_fence WHERE user_id=?",bytes(owner));
   }System.out.println("BACKUP_FENCE_RETIRED="+rows.size());
  }else if(args[0].equals("authorize-fixture")){
   var row=json.readTree(System.in.readNBytes(4097));var owner=UUID.fromString(row.path("owner").asText());var recording=UUID.fromString(row.path("recording").asText());var generation=UUID.fromString(row.path("generation").asText());
   if(db.queryForObject("SELECT COUNT(*) FROM recording r JOIN device d ON d.id=r.origin_device_id AND d.user_id=r.user_id WHERE r.user_id=? AND r.id=? AND d.display_name='P24 synthetic backup fixture'",Long.class,bytes(owner),bytes(recording))!=1)throw new IllegalArgumentException();
   try{new BackupDeletionFence(db,java.time.Clock.systemUTC(),true).generation(new com.ksh321.songrecord.api.storage.StorageObjectKeys.Final(owner,recording,generation));System.out.println("BACKUP_FIXTURE_FENCE=ACKNOWLEDGED");}
   catch(BackupDeletionFence.Awaiting pending){System.out.println("BACKUP_FIXTURE_FENCE=WAIT");}
  }else{
   byte[] raw=System.in.readNBytes(4_000_001);if(raw.length>4_000_000)throw new IllegalArgumentException();var list=json.readTree(raw);if(!list.isArray()||list.size()>10000)throw new IllegalArgumentException();int changed=0;
   for(var row:list){UUID id=UUID.fromString(row.path("id").asText());long revision=row.path("revision").asLong();if(revision<1)throw new IllegalArgumentException();
    changed+=db.update("UPDATE operational_backup_fence SET backup_ack_revision=?,backup_absent_at=? WHERE id=? AND revision=?",revision,row.path("absent").asBoolean()?java.sql.Timestamp.from(java.time.Instant.now()):null,bytes(id),revision);
   }System.out.println("BACKUP_LEDGER_ACK="+changed);
  }
 }catch(Exception error){System.err.println("BACKUP_LEDGER_OPERATOR_UNCONFIRMED: values suppressed");System.exit(2);}}
 static Map<String,Object> project(Map<String,Object> row,String time){var item=new LinkedHashMap<String,Object>();item.put("owner",uuid((byte[])row.get("user_id")).toString());item.put("type",row.get("entity_type"));item.put("entity",uuid((byte[])row.get("entity_id")).toString());if(row.get("object_generation")!=null)item.put("generation",uuid((byte[])row.get("object_generation")).toString());item.put("revision",((Number)row.get("revision")).longValue());var stamp=row.get(time);var instant=stamp instanceof java.sql.Timestamp value?value.toInstant():((java.time.LocalDateTime)stamp).toInstant(java.time.ZoneOffset.UTC);item.put("at",instant.toString());return item;}
}
