package com.ksh321.songrecord.api.retention;
import java.util.*;import org.springframework.jdbc.core.JdbcTemplate;import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** Fresh policy reads while the caller holds USER_SYNC. Clearable holds are not mandatory roles. */
final class CleanupProtection {
 static boolean automatic(JdbcTemplate db,UUID owner,UUID recording){
  var records=db.queryForList("SELECT song_id FROM recording WHERE user_id=? AND id=?",bytes(owner),bytes(recording));if(records.isEmpty() || records.getFirst().get("song_id")==null)return false;
  UUID song=uuid((byte[])records.getFirst().get("song_id"));var songs=db.queryForList("SELECT representative_recording_id FROM song WHERE user_id=? AND id=? AND lifecycle_state='ACTIVE'",bytes(owner),bytes(song));if(songs.isEmpty())return false;
  byte[] representative=(byte[])songs.getFirst().get("representative_recording_id");return RetentionRoles.calculate(new RetentionCandidates(db).forSong(owner,song),representative==null?null:uuid(representative)).recordingIds().contains(recording);
 }
 static boolean mandatory(JdbcTemplate db,UUID owner,UUID recording){return automatic(db,owner,recording)
  || !db.queryForList("SELECT slot_no FROM pin_slot WHERE user_id=? AND (current_recording_id=? OR pending_recording_id=?)",bytes(owner),bytes(recording),bytes(recording)).isEmpty()
  || !db.queryForList("SELECT id FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason='PENDING_REPLACEMENT'",bytes(owner),bytes(recording)).isEmpty();}
}
