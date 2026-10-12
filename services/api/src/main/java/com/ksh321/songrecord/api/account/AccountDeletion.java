package com.ksh321.songrecord.api.account;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.songs.SongQueryKeys;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;

/** Live identity proof and an already protected status token precede irrevocable acceptance. */
public final class AccountDeletion {
 private final JdbcTemplate db;private final AccountAccess access;private final LinkProofVerifier proofs;
 private final IdempotentMutations mutations;private final TransactionTemplate tx;private final Clock clock;
 private final SecureRandom random=new SecureRandom();
 public AccountDeletion(JdbcTemplate db,AccountAccess access,LinkProofVerifier proofs,IdempotentMutations mutations,PlatformTransactionManager manager,Clock clock){
  this.db=db;this.access=access;this.proofs=proofs;this.mutations=mutations;this.clock=clock;
  tx=new TransactionTemplate(manager);tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);tx.setTimeout(10);
 }
 public Map<String,Object> challenge(String auth,String device,String provider){
  if(provider==null||!Set.of("GOOGLE","KAKAO").contains(provider))throw bad();
  var account=access.authenticate(auth,device);
  return tx.execute(s->{var p=lock(account);var at=now();
   if(count("SELECT COUNT(*) FROM auth_identity WHERE user_id=? AND provider=?",b(p.userId()),provider)!=1)throw denied();
   if(count("SELECT COUNT(*) FROM account_deletion_challenge WHERE user_id=? AND created_at>?",b(p.userId()),at.minusMinutes(10))>=5)throw rate();
   var id=UUID.randomUUID();var nonce=token();
   db.update("INSERT INTO account_deletion_challenge(id,user_id,session_id,provider,nonce_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?)",b(id),b(p.userId()),b(p.sessionId()),provider,hash(nonce),at,at.plusMinutes(5));
   return Map.of("challenge_id",id.toString(),"nonce",nonce,"expires_at",wire(at.plusMinutes(5)));
  });
 }
 public Map<String,Object> prepare(String auth,String device,String challenge,String proof){
  var account=access.authenticate(auth,device);UUID id=uuid(challenge);var p=access.revalidate(account);
  var c=readChallenge(id,p,false);var identity=proofs.verify((String)c.get("provider"),proof,(byte[])c.get("nonce_hash"),time(c.get("created_at")).toInstant(ZoneOffset.UTC));
  return tx.execute(s->{var current=lock(account);var row=readChallenge(id,current,true);
   if(!identity.provider().equals(row.get("provider")) || count("SELECT COUNT(*) FROM auth_identity WHERE user_id=? AND provider=? AND provider_user_id=?",b(current.userId()),identity.provider(),identity.providerUserId())!=1)throw denied();
   var at=now();var prep=UUID.randomUUID();var token=token();
   db.update("UPDATE account_deletion_challenge SET verified_at=? WHERE id=?",at,b(id));
   db.update("INSERT INTO account_deletion_status(id,user_id,session_id,challenge_id,token_hash,prepared_at,prepare_expires_at) VALUES(?,?,?,?,?,?,?)",b(prep),b(current.userId()),b(current.sessionId()),b(id),hash(token),at,at.plusMinutes(10));
   var revision=db.queryForObject("SELECT revision FROM app_user WHERE id=?",Long.class,b(current.userId()));
   return Map.of("preparation_id",prep.toString(),"status_token",token,"reauth_proof",id.toString(),"base_revision",revision,"prepare_expires_at",wire(at.plusMinutes(10)));
  });
 }
 public IdempotentMutations.Reply accept(String auth,String device,String operation,String token,String body){
  var account=access.authenticate(auth,device);var owner=account.principal();
  var input=tools.jackson.databind.json.JsonMapper.builder().build().readTree(CanonicalRequest.canonical(body));
  if(!input.isObject()||!input.properties().stream().map(Map.Entry::getKey).collect(java.util.stream.Collectors.toSet()).equals(Set.of("preparation_id","base_revision","reauth_proof","scope","confirmed")))throw bad();
  UUID id=uuid(input.path("preparation_id").asText()),challenge=uuid(input.path("reauth_proof").asText());
  if(!input.path("base_revision").isIntegralNumber()||!input.path("base_revision").canConvertToLong()||input.path("base_revision").longValue()<1||!input.path("confirmed").isBoolean()||!input.path("confirmed").booleanValue()||!"ALL_ACCOUNT_DATA".equals(input.path("scope").asText()))throw bad();
  UUID op=uuid(operation);checkToken(token);
  return mutations.execute(account,operation,"POST","/v1/account/deletion-requests",body,()->{
   db.queryForList("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",b(owner.userId()));
   var p=lock(account);var rows=db.queryForList("SELECT * FROM account_deletion_status WHERE id=? FOR UPDATE",b(id));
   if(rows.size()!=1)throw denied();var row=rows.getFirst();
   if(!Arrays.equals((byte[])row.get("user_id"),b(p.userId()))||!Arrays.equals((byte[])row.get("session_id"),b(p.sessionId()))||!Arrays.equals((byte[])row.get("challenge_id"),b(challenge))||!MessageDigest.isEqual((byte[])row.get("token_hash"),hash(token)))throw denied();
   var at=now();if(!"PREPARED".equals(row.get("state"))||!time(row.get("prepare_expires_at")).isAfter(at))throw expired();
   var verified=db.queryForObject("SELECT verified_at FROM account_deletion_challenge WHERE id=?",java.sql.Timestamp.class,b(challenge));
   if(verified==null||!verified.toLocalDateTime().plusMinutes(5).isAfter(at))throw expired();
   long revision=db.queryForObject("SELECT revision FROM app_user WHERE id=?",Long.class,b(p.userId()));
   if(revision!=input.path("base_revision").longValue()||revision==Long.MAX_VALUE)throw conflict();
   db.update("UPDATE app_user SET status='DELETING',revision=revision+1,updated_at=? WHERE id=?",at,b(p.userId()));
   db.update("UPDATE auth_session SET revoked_at=COALESCE(revoked_at,?),updated_at=? WHERE user_id=?",at,at,b(p.userId()));
   db.update("INSERT INTO deletion_ledger(id,user_id,entity_type,entity_id,revision,purged_at) VALUES(?,?,'USER',?,?,?)",b(UUID.randomUUID()),b(p.userId()),b(p.userId()),revision+1,at);
   var job=UUID.randomUUID();
   db.update("INSERT INTO job(id,user_id,type,aggregate_id,dedupe_key,payload,state,run_after,created_at,updated_at) VALUES(?,?,'ACCOUNT_DELETE',?,?,?,'QUEUED',?,?,?)",b(job),b(p.userId()),b(id),("account-delete:"+p.userId()).getBytes(StandardCharsets.US_ASCII),"{\"preparation_id\":\""+id+"\"}",at,at,at);
   db.update("UPDATE account_deletion_status SET state='ACCEPTED',accepted_at=?,expires_at=?,backup_purge_due_at=?,operation_id=?,request_hash=? WHERE id=?",at,at.plusDays(30),at.plusDays(7),b(op),CanonicalRequest.hash("POST","/v1/account/deletion-requests",body),b(id));
   return new IdempotentMutations.Reply(202,"{\"operation_id\":\""+op+"\",\"status_path\":\"/v1/account/deletion-status/"+id+"\",\"accepted_at\":\""+wire(at)+"\",\"expires_at\":\""+wire(at.plusDays(30))+"\"}");
  });
 }
 /** Only the dedicated proof works after sessions are revoked. No account/target identifiers leave here. */
 public Map<String,Object> status(String preparation,String token){
  UUID id;try{id=uuid(preparation);}catch(ApiException invalid){throw denied();}checkToken(token);
  return tx.execute(s->{var rows=db.queryForList("SELECT * FROM account_deletion_status WHERE id=? FOR UPDATE",b(id));
  if(rows.size()!=1||!MessageDigest.isEqual((byte[])rows.getFirst().get("token_hash"),hash(token)))throw denied();var row=rows.getFirst();
  var expiry=time(row.get(row.get("accepted_at")==null?"prepare_expires_at":"expires_at"));
  if(!expiry.isAfter(now()))throw new ApiException(HttpStatus.GONE,"STATUS_TOKEN_EXPIRED","확인증이 만료됐어요.",false,Map.of());
  var at=now();var window=row.get("query_window_at");
  if(window==null||!time(window).plusMinutes(1).isAfter(at))db.update("UPDATE account_deletion_status SET query_window_at=?,query_count=1 WHERE id=?",at,b(id));
  else {if(((Number)row.get("query_count")).intValue()>=60)throw rate();db.update("UPDATE account_deletion_status SET query_count=query_count+1 WHERE id=?",b(id));}
  Map<String,Object> result=new LinkedHashMap<>();result.put("status",row.get("state"));result.put("retrying",row.get("retrying"));
  for(var key:List.of("accepted_at","service_deleted_at","backup_purge_due_at","completed_at","expires_at"))result.put(key,row.get(key)==null?null:wire(time(row.get(key))));
  return result;});
 }
 private SessionService.Principal lock(AccountAccess.Account account){var p=access.revalidate(account);db.queryForList("SELECT id FROM app_user WHERE id=? FOR UPDATE",b(p.userId()));return access.revalidate(account);}
 private Map<String,Object> readChallenge(UUID id,SessionService.Principal p,boolean locking){var rows=db.queryForList("SELECT * FROM account_deletion_challenge WHERE id=? AND user_id=? AND session_id=?"+(locking?" FOR UPDATE":""),b(id),b(p.userId()),b(p.sessionId()));if(rows.size()!=1)throw denied();var r=rows.getFirst();if(r.get("verified_at")!=null||!time(r.get("expires_at")).isAfter(now()))throw expired();return r;}
 private long count(String sql,Object...args){return db.queryForObject(sql,Long.class,args);}
 private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);}
 private static LocalDateTime time(Object value){return value instanceof java.sql.Timestamp t?t.toLocalDateTime():(LocalDateTime)value;}
 private static String wire(LocalDateTime value){return java.time.format.DateTimeFormatter.ISO_INSTANT.format(value.toInstant(ZoneOffset.UTC));}
 private String token(){byte[] b=new byte[32];random.nextBytes(b);return Base64.getUrlEncoder().withoutPadding().encodeToString(b);}
 private static void checkToken(String token){if(token==null||!token.matches("[A-Za-z0-9_-]{43}"))throw denied();}
 private static byte[] hash(String value){try{return MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.US_ASCII));}catch(NoSuchAlgorithmException e){throw new IllegalStateException("SHA-256 unavailable");}}
 private static byte[] b(UUID id){return SongQueryKeys.bytes(id);}
 private static UUID uuid(String id){try{var v=UUID.fromString(id);if(!v.toString().equals(id))throw bad();return v;}catch(IllegalArgumentException|NullPointerException e){throw bad();}}
 private static ApiException bad(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","입력을 확인해 주세요.",false,Map.of());}
 private static ApiException denied(){return new ApiException(HttpStatus.NOT_FOUND,"DELETION_PROOF_INVALID","확인증 또는 소유 확인이 유효하지 않아요.",false,Map.of());}
 private static ApiException expired(){return new ApiException(HttpStatus.CONFLICT,"REAUTH_REQUIRED","최근 재인증을 다시 진행해 주세요.",false,Map.of());}
 private static ApiException conflict(){return new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT","계정 상태를 다시 확인해 주세요.",false,Map.of());}
 private static ApiException rate(){return new ApiException(HttpStatus.TOO_MANY_REQUESTS,"DELETION_RATE_LIMIT","잠시 후 다시 시도해 주세요.",true,Map.of());}
}
