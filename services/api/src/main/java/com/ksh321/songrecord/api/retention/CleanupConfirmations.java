package com.ksh321.songrecord.api.retention;
import java.time.*;import java.util.*;import org.springframework.context.annotation.Profile;import org.springframework.stereotype.Component;import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.transaction.PlatformTransactionManager;import org.springframework.http.HttpStatus;import tools.jackson.databind.json.JsonMapper;
import com.ksh321.songrecord.api.auth.AccountAccess;import com.ksh321.songrecord.api.idempotency.*;import com.ksh321.songrecord.api.locking.LockOrder;import com.ksh321.songrecord.api.web.ApiException;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
/** One opaque random token per owner/generation/checksum/revision. Confirmation never starts deletion. */
@Component @Profile("!bootstrap")
public final class CleanupConfirmations {
 private static final JsonMapper JSON=new JsonMapper();private final JdbcTemplate db;private final AccountAccess access;private final IdempotentMutations mutations;private final Clock clock;
 @Autowired public CleanupConfirmations(JdbcTemplate db,AccountAccess access,PlatformTransactionManager manager,IdempotentMutations mutations){this(db,access,mutations,Clock.systemUTC());}
 CleanupConfirmations(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,Clock clock){this.db=db;this.access=access;this.mutations=mutations;this.clock=clock;}
 public IdempotentMutations.Reply preview(String auth,String device,String operation,String body){
  var account=access.authenticate(auth,device);var root=JSON.readTree(CanonicalRequest.canonical(body));
  if(!root.isObject() || root.size()!=1 || !root.has("recording_ids") || !root.get("recording_ids").isArray() || root.get("recording_ids").size()<1 || root.get("recording_ids").size()>20)throw invalid();
  var ids=new TreeSet<UUID>(Comparator.comparing(UUID::toString));for(var n:root.get("recording_ids")){if(!n.isTextual() || !ids.add(PinSlots.parse(n.asText())))throw invalid();}
  return mutations.execute(account,operation,"POST","/v1/storage/cleanup-previews",body,()->{
   UUID owner=lock(account);var items=new ArrayList<Map<String,Object>>();
   for(UUID id:ids){var asset=asset(owner,id);if(CleanupProtection.mandatory(db,owner,id))throw error("FILE_STILL_PROTECTED");
    var rows=db.queryForList("SELECT id,state,created_at,generation,expected_sha256,expected_cloud_revision FROM cloud_cleanup WHERE user_id=? AND recording_id=? AND state IN ('WAITING_CONFIRMATION','CONFIRMED','DELETING','RETRY_WAIT') FOR UPDATE",bytes(owner),bytes(id));UUID token=null;Instant issued=now();
    if(!rows.isEmpty()){var prior=rows.getFirst();String state=(String)prior.get("state");Instant created=instant(prior.get("created_at"));
     boolean same=Arrays.equals((byte[])prior.get("generation"),(byte[])asset.get("generation")) && Objects.equals(prior.get("expected_sha256"),asset.get("sha256")) && ((Number)prior.get("expected_cloud_revision")).longValue()==((Number)asset.get("cloud_revision")).longValue();
     if(state.equals("WAITING_CONFIRMATION") && same && created.plusSeconds(900).isAfter(now())){token=uuid((byte[])prior.get("id"));issued=created;}
     else if(Set.of("DELETING","RETRY_WAIT").contains(state) || state.equals("CONFIRMED") && created.plusSeconds(900).isAfter(now()))throw error("FILE_CLEANUP_IN_PROGRESS");
     else db.update("UPDATE cloud_cleanup SET state='EXPIRED',completed_at=?,updated_at=? WHERE user_id=? AND id=?",stamp(now()),stamp(now()),bytes(owner),prior.get("id"));
    }
    if(token==null){token=UUID.randomUUID();db.update("INSERT INTO cloud_cleanup(id,user_id,recording_id,generation,expected_sha256,expected_cloud_revision,state,created_at,updated_at) VALUES(?,?,?,?,?,?,'WAITING_CONFIRMATION',?,?)",bytes(token),bytes(owner),bytes(id),asset.get("generation"),asset.get("sha256"),asset.get("cloud_revision"),stamp(issued),stamp(issued));}
    var item=new LinkedHashMap<String,Object>();item.put("token",token.toString());item.put("user_id",owner.toString());item.put("recording_id",id.toString());item.put("generation",uuid((byte[])asset.get("generation")).toString());item.put("sha256",asset.get("sha256"));item.put("size_bytes",asset.get("verified_size"));item.put("cloud_revision",asset.get("cloud_revision"));item.put("expires_at",issued.plusSeconds(900).toString());item.put("hold_reasons",db.queryForList("SELECT DISTINCT reason FROM cloud_hold WHERE user_id=? AND recording_id=? ORDER BY reason",String.class,bytes(owner),bytes(id)));items.add(item);
   }
   return new IdempotentMutations.Reply(200,JSON.writeValueAsString(Map.of("items",items)));
  });
 }
 public IdempotentMutations.Reply confirm(String auth,String device,String operation,String body){
  var account=access.authenticate(auth,device);var root=JSON.readTree(CanonicalRequest.canonical(body));
  if(!root.isObject() || !root.has("token") || !root.has("mode") || !root.has("device_id") || !root.has("sha256") || !root.get("token").isTextual() || !root.get("mode").isTextual() || !root.get("device_id").isTextual() || !root.get("sha256").isTextual())throw invalid();
  UUID token=PinSlots.parse(root.get("token").asText());String mode=root.get("mode").asText(),hash=root.get("sha256").asText();
  if(!Set.of("LOCAL_VERIFIED","USER_CONFIRMED_LOSS").contains(mode) || !hash.matches("[0-9a-f]{64}") || !PinSlots.parse(root.get("device_id").asText()).equals(account.principal().deviceId()) || root.size()!=(mode.equals("LOCAL_VERIFIED")?4:5) || mode.equals("USER_CONFIRMED_LOSS") && (!root.has("understands_loss") || !root.get("understands_loss").isBoolean() || !root.get("understands_loss").asBoolean()))throw invalid();
  return mutations.execute(account,operation,"POST","/v1/storage/cleanup-confirmations",body,()->{
   UUID owner=lock(account);var found=db.queryForList("SELECT recording_id FROM cloud_cleanup WHERE user_id=? AND id=?",bytes(owner),bytes(token));if(found.isEmpty())throw error("CLEANUP_TOKEN_INVALID");UUID id=uuid((byte[])found.getFirst().get("recording_id"));var asset=asset(owner,id);
   var rows=db.queryForList("SELECT generation,expected_sha256,expected_cloud_revision,state,created_at,confirmation_mode FROM cloud_cleanup WHERE user_id=? AND id=? FOR UPDATE",bytes(owner),bytes(token));var row=rows.getFirst();Instant expiry=instant(row.get("created_at")).plusSeconds(900);
   if(!expiry.isAfter(now()))throw error("CLEANUP_TOKEN_EXPIRED");
   if(!Arrays.equals((byte[])row.get("generation"),(byte[])asset.get("generation")) || !hash.equals(row.get("expected_sha256")) || !hash.equals(asset.get("sha256")) || ((Number)row.get("expected_cloud_revision")).longValue()!=((Number)asset.get("cloud_revision")).longValue())throw error("CLEANUP_OBJECT_CHANGED");
   if(CleanupProtection.mandatory(db,owner,id))throw error("FILE_STILL_PROTECTED");
   String state=(String)row.get("state");if(!state.equals("WAITING_CONFIRMATION") && !(state.equals("CONFIRMED") && mode.equals(row.get("confirmation_mode"))))throw error("CLEANUP_STATE_CONFLICT");
   if(state.equals("WAITING_CONFIRMATION"))db.update("UPDATE cloud_cleanup SET state='CONFIRMED',confirmation_mode=?,confirmed_at=?,confirmation_expires_at=?,updated_at=? WHERE user_id=? AND id=?",mode,stamp(now()),stamp(expiry),stamp(now()),bytes(owner),bytes(token));
   return new IdempotentMutations.Reply(200,JSON.writeValueAsString(Map.of("token",token.toString(),"state","CONFIRMED","expires_at",expiry.toString())));
  });
 }
 private UUID lock(AccountAccess.Account account){UUID owner=access.revalidate(account).userId();LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());if(db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner)).isEmpty())throw error("CLEANUP_TOKEN_INVALID");access.revalidate(account);return owner;}
 private Map<String,Object> asset(UUID owner,UUID id){LockOrder.before(LockOrder.Rank.RECORDING_ASSET,owner+"/"+id);var rows=db.queryForList("SELECT generation,sha256,verified_size,cloud_revision FROM recording_asset WHERE user_id=? AND recording_id=? AND cloud_state='STORED' FOR UPDATE",bytes(owner),bytes(id));if(rows.isEmpty())throw error("FILE_NOT_STORED");return rows.getFirst();}
 static Instant instant(Object value){if(value instanceof java.sql.Timestamp t)return t.toInstant();if(value instanceof LocalDateTime t)return t.toInstant(ZoneOffset.UTC);throw new IllegalStateException("CLEANUP_TIME_INVALID");}
 private Instant now(){return clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MILLIS);}private static java.sql.Timestamp stamp(Instant instant){return java.sql.Timestamp.from(instant);}
 private static ApiException invalid(){return PinSlots.invalid();}private static ApiException error(String code){return new ApiException(HttpStatus.CONFLICT,code,"서버 사본 상태와 보존 확인을 다시 확인해 주세요.",false,Map.of());}
}
