package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** An email string never enters this boundary. Unknown subjects cannot create a new account. */
public final class DeletionWebOwnership {
 public interface Verifier {VerifiedProviderIdentity verify(String provider,String proof,byte[] nonce,Instant startedAt);}
 private final JdbcTemplate db;private final AccountRegistrationService registrations;private final SessionService sessions;
 private final AccountDeletion deletion;private final Verifier verifier;private final Clock clock;private final String pepper;
 private final Map<String,String> clients;private final TransactionTemplate tx;private final SecureRandom random=new SecureRandom();
 public DeletionWebOwnership(JdbcTemplate db,AccountRegistrationService registrations,SessionService sessions,AccountDeletion deletion,Verifier verifier,Clock clock,String pepper,Map<String,String> clients,PlatformTransactionManager manager){
  this.db=db;this.registrations=registrations;this.sessions=sessions;this.deletion=deletion;this.verifier=verifier;this.clock=clock;this.pepper=pepper;this.clients=Map.copyOf(clients);
  tx=new TransactionTemplate(manager);tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);tx.setTimeout(10);
 }
 public Map<String,Object> configuration(){return Map.of("providers",clients,"enabled",pepper.length()>=32&&!clients.isEmpty());}
 public Map<String,Object> challenge(String provider,String requester){
  if(pepper.length()<32||provider==null||!clients.containsKey(provider))throw unavailable();
  if(requester==null||requester.length()>128)throw invalid();var requesterHash=requesterHash(requester);
  return tx.execute(s->{var at=now();
   var rows=db.queryForList("SELECT * FROM deletion_web_rate WHERE requester_hash=? FOR UPDATE",requesterHash);
   if(rows.isEmpty()){
    try{db.update("INSERT INTO deletion_web_rate(requester_hash,window_at,request_count) VALUES(?,?,0)",requesterHash,at);}catch(DuplicateKeyException duplicate){/* Concurrent first request owns this same rate key. */}
    rows=db.queryForList("SELECT * FROM deletion_web_rate WHERE requester_hash=? FOR UPDATE",requesterHash);
   }
   var rate=rows.getFirst();boolean reset=!time(rate.get("window_at")).plusMinutes(10).isAfter(at);
   int count=reset?0:((Number)rate.get("request_count")).intValue();if(count>=10)throw new ApiException(HttpStatus.TOO_MANY_REQUESTS,"DELETION_WEB_RATE_LIMIT","잠시 후 다시 시도해 주세요.",true,Map.of());
   db.update("UPDATE deletion_web_rate SET window_at=?,request_count=? WHERE requester_hash=?",reset?at:rate.get("window_at"),count+1,requesterHash);
   var id=UUID.randomUUID();var nonce=token();var state=token();
   db.update("INSERT INTO deletion_web_challenge(id,provider,nonce_hash,state_hash,requester_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?)",bytes(id),provider,hash(nonce),hash(state),requesterHash,at,at.plusMinutes(5));
   return Map.of("challenge_id",id.toString(),"nonce",nonce,"state",state,"expires_at",at.plusMinutes(5).toInstant(ZoneOffset.UTC).toString());
  });
 }
 public Map<String,Object> prepare(String challenge,String proof){
  UUID id=id(challenge);var before=challengeRow(id,false);String provider=(String)before.get("provider");
  var identity=verifier.verify(provider,proof,(byte[])before.get("nonce_hash"),time(before.get("created_at")).toInstant(ZoneOffset.UTC));
  if(!provider.equals(identity.provider()))throw invalid();
  tx.executeWithoutResult(s->{challengeRow(id,true);db.update("UPDATE deletion_web_challenge SET consumed_at=? WHERE id=?",now(),bytes(id));});
  var owner=registrations.registerExisting(identity,"탈퇴 웹 소유 확인");var tokens=sessions.issue(owner);
  try{
   var prepared=deletion.prepareVerified("Bearer "+tokens.accessToken(),owner.deviceId().toString(),identity,time(before.get("created_at")).toInstant(ZoneOffset.UTC),(byte[])before.get("nonce_hash"));
   var result=new LinkedHashMap<String,Object>(prepared);result.put("user_id",owner.userId().toString());result.put("device_id",owner.deviceId().toString());result.put("access_token",tokens.accessToken());return result;
  }catch(RuntimeException failure){sessions.logout(tokens.refreshToken(),owner.deviceId());throw failure;}
 }
 public Map<String,Object> kakaoState(String state){
  if(state==null||!state.matches("[A-Za-z0-9_-]{43}"))throw invalid();
  var rows=db.queryForList("SELECT * FROM deletion_web_challenge WHERE state_hash=? AND provider='KAKAO'",hash(state));
  if(rows.size()!=1)throw invalid();var row=rows.getFirst();if(row.get("consumed_at")!=null||!time(row.get("expires_at")).isAfter(now()))throw invalid();
  return row;
 }
 public void prune(){var at=now();tx.executeWithoutResult(s->{db.update("DELETE FROM deletion_web_challenge WHERE expires_at<=?",at.minusMinutes(5));db.update("DELETE FROM deletion_web_rate WHERE window_at<=?",at.minusMinutes(10));});}
 private Map<String,Object> challengeRow(UUID id,boolean lock){var rows=db.queryForList("SELECT * FROM deletion_web_challenge WHERE id=?"+(lock?" FOR UPDATE":""),bytes(id));if(rows.size()!=1)throw invalid();var r=rows.getFirst();if(r.get("consumed_at")!=null||!time(r.get("expires_at")).isAfter(now()))throw invalid();return r;}
 private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(java.time.temporal.ChronoUnit.MILLIS);}
 private static LocalDateTime time(Object v){return v instanceof java.sql.Timestamp t?t.toLocalDateTime():(LocalDateTime)v;}
 private String token(){byte[] b=new byte[32];random.nextBytes(b);return Base64.getUrlEncoder().withoutPadding().encodeToString(b);}
 static byte[] hash(String s){try{return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));}catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}}
 private byte[] requesterHash(String requester){try{var mac=javax.crypto.Mac.getInstance("HmacSHA256");mac.init(new javax.crypto.spec.SecretKeySpec(pepper.getBytes(StandardCharsets.UTF_8),"HmacSHA256"));return mac.doFinal(requester.getBytes(StandardCharsets.UTF_8));}catch(java.security.GeneralSecurityException e){throw new IllegalStateException("Rate hash unavailable");}}
 private static UUID id(String text){try{var id=UUID.fromString(text);if(!id.toString().equals(text))throw invalid();return id;}catch(IllegalArgumentException|NullPointerException e){throw invalid();}}
 private static ApiException invalid(){return new ApiException(HttpStatus.UNAUTHORIZED,"DELETION_OWNER_UNVERIFIED","현재 계정의 소유 확인을 다시 진행해 주세요.",false,Map.of());}
 static ApiException unavailable(){return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"DELETION_WEB_NOT_CONFIGURED","웹 소유 확인 설정이 준비되지 않았어요. 앱 내 탈퇴 경로를 이용해 주세요.",true,Map.of());}
}
