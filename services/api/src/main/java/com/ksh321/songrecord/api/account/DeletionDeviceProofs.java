package com.ksh321.songrecord.api.account;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.web.ApiException;
import org.springframework.http.HttpStatus;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** A revoked refresh proof confirms only its original device's deletion, never login. */
public final class DeletionDeviceProofs {
 private final JdbcTemplate db;private final Clock clock;
 public DeletionDeviceProofs(JdbcTemplate db,Clock clock){this.db=db;this.clock=clock;}
 public Map<String,Object> confirm(String owner,String device,String proof){
  UUID user=parse(owner),id=parse(device);
  if(proof==null||!proof.matches("sr_r_[A-Za-z0-9_-]{43}"))throw denied();
  var rows=db.queryForList("SELECT expires_at FROM account_deletion_device_proof WHERE token_hash=? AND owner_id=? AND device_id=?",DeletionWebOwnership.hash(proof),bytes(user),bytes(id));
  if(rows.size()!=1)throw denied();
  var value=rows.getFirst().get("expires_at");var expiry=value instanceof java.sql.Timestamp t?t.toLocalDateTime():(LocalDateTime)value;
  if(!expiry.isAfter(LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC)))throw denied();
  if(db.queryForList("SELECT id FROM deletion_ledger WHERE user_id=? AND entity_type='USER' AND entity_id=?",bytes(user),bytes(user)).isEmpty())throw denied();
  return Map.of("deletion_confirmed",true);
 }
 private static UUID parse(String value){try{var id=UUID.fromString(value);if(!id.toString().equals(value))throw denied();return id;}catch(IllegalArgumentException|NullPointerException e){throw denied();}}
 private static ApiException denied(){return new ApiException(HttpStatus.NOT_FOUND,"DELETION_DEVICE_UNCONFIRMED","이 기기 계정의 삭제를 확인하지 못했어요.",false,Map.of());}
}
