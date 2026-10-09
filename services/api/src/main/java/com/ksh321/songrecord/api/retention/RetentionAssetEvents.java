package com.ksh321.songrecord.api.retention;
import java.time.*;import java.util.*;import org.springframework.jdbc.core.JdbcTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** The caller holds USER_SYNC and the owned asset; no storage key or signed URL enters the feed. */
final class RetentionAssetEvents {
 static void publish(JdbcTemplate db,UUID owner,UUID recording,long revision,Clock clock){
  var rows=db.query("SELECT recording_id,cloud_state,blocked_reason,generation,verified_size,sha256,stored_at,cloud_revision,created_at,updated_at FROM recording_asset WHERE user_id=? AND recording_id=?",(rs,n)->{var out=new LinkedHashMap<String,Object>();var meta=rs.getMetaData();for(int i=1;i<=meta.getColumnCount();i++){String name=meta.getColumnLabel(i).toLowerCase(Locale.ROOT);Object v;if(Set.of("stored_at","created_at","updated_at").contains(name)){var time=rs.getObject(i,LocalDateTime.class);v=time==null?null:time.toInstant(ZoneOffset.UTC).toString();}else{v=rs.getObject(i);if(v instanceof byte[] b)v=uuid(b).toString();}out.put(name,v);}return out;},bytes(owner),bytes(recording));
  if(rows.size()!=1)throw new IllegalStateException("Asset event identity lost");long seq=db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner)),next=Math.incrementExact(seq);var now=CleanupConfirmations.stamp(clock.instant());
  db.update("INSERT INTO change_log(user_id,change_seq,entity_type,entity_id,revision,operation,payload,created_at,expires_at) VALUES(?,?,'RECORDING_ASSET',?,?,'UPSERT',?,?,?)",bytes(owner),next,bytes(recording),revision,new tools.jackson.databind.json.JsonMapper().writeValueAsString(rows.getFirst()),now,now.plusDays(90));
  if(db.update("UPDATE user_sync_state SET last_change_seq=?,updated_at=? WHERE user_id=? AND last_change_seq=?",next,now,bytes(owner),seq)!=1)throw new IllegalStateException("Cleanup sync state changed");
 }
}
