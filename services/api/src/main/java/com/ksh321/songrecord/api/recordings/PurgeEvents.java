package com.ksh321.songrecord.api.recordings;
import java.time.*;import java.util.*;import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.sync.AccountChanges;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Trusted maintenance caller holds USER_SYNC before publishing owned tombstones. */
final class PurgeEvents {
 static void publish(JdbcTemplate db,UUID owner,List<AccountChanges.Change> events,Clock clock){
  long start=db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner)),seq=start;var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(java.time.temporal.ChronoUnit.MILLIS);
  for(var e:events){seq=Math.incrementExact(seq);db.update("INSERT INTO change_log(user_id,change_seq,entity_type,entity_id,revision,operation,payload,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?)",bytes(owner),seq,e.entity().name(),bytes(e.id()),e.revision(),e.operation().name(),e.payload(),now,now.plusDays(90));}
  if(db.update("UPDATE user_sync_state SET last_change_seq=?,updated_at=? WHERE user_id=? AND last_change_seq=?",seq,now,bytes(owner),start)!=1)throw new IllegalStateException("Purge sync state changed");
 }
}
