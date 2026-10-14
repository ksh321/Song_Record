package com.ksh321.songrecord.api.operations;
import java.io.*;
import java.util.*;
import org.flywaydb.core.Flyway;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

/** Only a fresh disposable restore DB and its scoped user; never the live validation database. */
public final class RestoreValidationOperator {
 public static void main(String[] args){try{
  if(args.length!=1||!Set.of("migrate","metadata","check").contains(args[0]))throw new IllegalArgumentException();
  byte[] raw=System.in.readNBytes(4097);if(raw.length>4096)throw new IllegalArgumentException();var p=new Properties();p.load(new ByteArrayInputStream(raw));
  String name=p.getProperty("database",""),user=p.getProperty("user",""),password=p.getProperty("password","");
  if(!name.matches("song_record_restore_[0-9a-f]{32}")||!user.matches("sr_restore_[0-9a-f]{16}")||!password.matches("[A-Za-z0-9_-]{43}"))throw new IllegalArgumentException();
  var source=new DriverManagerDataSource("jdbc:mysql://mysql:3306/"+name+"?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true",user,password);var db=new JdbcTemplate(source);var json=new tools.jackson.databind.json.JsonMapper();
  if(args[0].equals("migrate")){
   var result=Flyway.configure().dataSource(source).locations("classpath:db/migration").load().migrate();
   System.out.println("RESTORE_MIGRATIONS="+result.migrationsExecuted);
  }else if(args[0].equals("metadata")){
   var tables=new TreeMap<String,Map<String,Object>>();
   for(var row:db.queryForList("SELECT c.table_name,c.column_name FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name WHERE c.table_schema=? AND t.table_type='BASE TABLE' ORDER BY c.table_name,c.ordinal_position",name)){
    String table=(String)row.get("TABLE_NAME");var item=tables.computeIfAbsent(table,k->new LinkedHashMap<>(Map.of("columns",new ArrayList<String>(),"parents",new ArrayList<String>())));((List<String>)item.get("columns")).add((String)row.get("COLUMN_NAME"));
   }
   for(var row:db.queryForList("SELECT DISTINCT table_name,referenced_table_name FROM information_schema.key_column_usage WHERE table_schema=? AND referenced_table_name IS NOT NULL",name)){var item=tables.get(row.get("TABLE_NAME"));if(item!=null)((List<String>)item.get("parents")).add((String)row.get("REFERENCED_TABLE_NAME"));}
   System.out.println(json.writeValueAsString(tables));
  }else{
   var files=new ArrayList<Map<String,Object>>();
   for(var row:db.queryForList("SELECT a.user_id,a.recording_id,a.generation,a.object_key,a.sha256,a.verified_size FROM recording_asset a JOIN recording r ON r.id=a.recording_id AND r.user_id=a.user_id WHERE a.cloud_state IN ('STORED','DELETING')")){
    var item=new LinkedHashMap<String,Object>();item.put("owner",com.ksh321.songrecord.api.songs.SongQueryKeys.uuid((byte[])row.get("user_id")).toString());item.put("recording",com.ksh321.songrecord.api.songs.SongQueryKeys.uuid((byte[])row.get("recording_id")).toString());item.put("generation",com.ksh321.songrecord.api.songs.SongQueryKeys.uuid((byte[])row.get("generation")).toString());item.put("key",row.get("object_key"));item.put("sha256",row.get("sha256"));item.put("size",row.get("verified_size"));files.add(item);
   }
   System.out.println(json.writeValueAsString(Map.of("files",files,"users",db.queryForObject("SELECT COUNT(*) FROM app_user",Long.class),"recordings",db.queryForObject("SELECT COUNT(*) FROM recording",Long.class))));
  }
 }catch(Exception error){System.err.println("RESTORE_VALIDATION_UNCONFIRMED: values suppressed");System.exit(2);}}
}
