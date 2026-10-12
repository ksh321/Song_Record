package com.ksh321.songrecord.api.account;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.idempotency.*;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.sql.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.MultiValueMap;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;

/** Demand only. Never changes entitlements, pins or upload authorization. */
public final class StorageRequests {
 private static final JsonMapper JSON=new JsonMapper();
 private final JdbcTemplate db;private final AccountAccess access;private final IdempotentMutations mutations;
 private final KeysetPages pages;private final Clock clock;
 public StorageRequests(JdbcTemplate db,AccountAccess access,IdempotentMutations mutations,KeysetPages pages,Clock clock){this.db=db;this.access=access;this.mutations=mutations;this.pages=pages;this.clock=clock;}
 public IdempotentMutations.Reply create(String auth,String device,String operation,String body){
  var account=access.authenticate(auth,device);CanonicalRequest.canonical(body);var root=JSON.readTree(body);
  if(!root.isObject() || root.size()!=2 || !root.has("id") || !root.has("types") || !root.get("id").isTextual() || !root.get("types").isArray())throw invalid();
  UUID id=parse(root.get("id").asText());var types=new TreeSet<String>();
  for(var value:root.get("types")){if(!value.isTextual() || !Set.of("PIN_LIMIT","STORAGE_QUOTA").contains(value.asText()) || !types.add(value.asText()))throw invalid();}
  if(types.isEmpty())throw invalid();UUID owner=account.principal().userId();
  // Even a not-yet-pruned common receipt cannot revive a 90-day-expired ID.
  var known=db.queryForList("SELECT user_id,received_at FROM storage_request_ledger WHERE id=?",bytes(id));
  if(!known.isEmpty()){requireOwner(known.getFirst(),owner);if(expired(time(known.getFirst().get("received_at"))))throw expired();}
  return mutations.execute(account,operation,"POST","/v1/storage/requests",body,()->{
   access.revalidate(account);LockOrder.before(LockOrder.Rank.USER_SYNC,owner.toString());
   db.queryForMap("SELECT user_id FROM user_sync_state WHERE user_id=? FOR UPDATE",bytes(owner));access.revalidate(account);
   var existing=db.queryForList("SELECT user_id,received_at FROM storage_request_ledger WHERE id=?",bytes(id));
   if(!existing.isEmpty()){
    requireOwner(existing.getFirst(),owner);if(expired(time(existing.getFirst().get("received_at"))))throw expired();
    var rows=db.query("SELECT * FROM storage_request_body WHERE user_id=? AND id=?",(r,n)->wire(r),bytes(owner),bytes(id));
    if(rows.isEmpty())throw expired();var result=rows.getFirst();
    if(!new TreeSet<>((List<String>)result.get("types")).equals(types))throw conflict("REQUEST_ID_CONFLICT");
    mark(owner,id,operation,time(existing.getFirst().get("received_at")));
    return reply(200,result);
   }
   var at=now();var day=at.toLocalDate();
   boolean prior=db.queryForObject("SELECT COUNT(*) FROM storage_request_ledger WHERE user_id=? AND received_at>=? AND received_at<?",Long.class,bytes(owner),Timestamp.valueOf(day.atStartOfDay()),Timestamp.valueOf(day.plusDays(1).atStartOfDay()))>0;
   var usage=db.queryForMap("SELECT s.used_bytes,e.quota_bytes,e.pinned_limit FROM storage_usage s JOIN user_entitlement e ON e.user_id=s.user_id WHERE s.user_id=?",bytes(owner));
   long pins=db.queryForObject("SELECT COUNT(*) FROM pin_slot WHERE user_id=? AND (current_recording_id IS NOT NULL OR pending_recording_id IS NOT NULL)",Long.class,bytes(owner));
   try{db.update("INSERT INTO storage_request_ledger(id,user_id,received_at) VALUES(?,?,?)",bytes(id),bytes(owner),Timestamp.valueOf(at));}
   catch(DuplicateKeyException e){throw missing();}
   db.update("INSERT INTO storage_request_body(id,user_id,pin_limit,storage_quota,received_at,pinned_used,pinned_limit,used_bytes,quota_bytes) VALUES(?,?,?,?,?,?,?,?,?)",bytes(id),bytes(owner),types.contains("PIN_LIMIT"),types.contains("STORAGE_QUOTA"),Timestamp.valueOf(at),pins,usage.get("pinned_limit"),usage.get("used_bytes"),usage.get("quota_bytes"));
   int pin=types.contains("PIN_LIMIT")?1:0,quota=types.contains("STORAGE_QUOTA")?1:0,unique=prior?0:1;
   if(db.update("UPDATE storage_request_daily SET request_total=request_total+1,pin_requests=pin_requests+?,quota_requests=quota_requests+?,unique_users=unique_users+? WHERE period_date=?",pin,quota,unique,java.sql.Date.valueOf(day))==0){
    try{db.update("INSERT INTO storage_request_daily VALUES(?,1,?,?,?)",java.sql.Date.valueOf(day),pin,quota,unique);}
    catch(DuplicateKeyException e){db.update("UPDATE storage_request_daily SET request_total=request_total+1,pin_requests=pin_requests+?,quota_requests=quota_requests+?,unique_users=unique_users+? WHERE period_date=?",pin,quota,unique,java.sql.Date.valueOf(day));}
   }
   mark(owner,id,operation,at);
   return reply(201,db.queryForObject("SELECT * FROM storage_request_body WHERE user_id=? AND id=?",(r,n)->wire(r),bytes(owner),bytes(id)));
  });
 }
 public Map<String,Object> get(String auth,String device,String rawId){
  var account=access.authenticate(auth,device);UUID id=parse(rawId);var rows=db.query("SELECT * FROM storage_request_body WHERE user_id=? AND id=? AND received_at>?",(r,n)->wire(r),bytes(account.principal().userId()),bytes(id),Timestamp.valueOf(now().minusDays(90)));
  access.revalidate(account);if(rows.isEmpty())throw missing();return rows.getFirst();
 }
 public KeysetPages.Page<Map<String,Object>> list(String auth,String device,MultiValueMap<String,String> params){
  var account=access.authenticate(auth,device);for(var e:params.entrySet())if(!Set.of("limit","cursor").contains(e.getKey()) || e.getValue().size()!=1)throw invalid();
  int limit=50;try{if(params.containsKey("limit")){String v=params.getFirst("limit");if(v==null || !v.matches("[1-9][0-9]{0,2}"))throw invalid();limit=PageCursor.pageSize(Integer.parseInt(v));}}catch(NumberFormatException e){throw invalid();}
  return pages.query(account,new PageCursor.Query("storage_requests","RECEIVED_DESC","SR-DEMAND-1","{}",limit),params.getFirst("cursor"),new Source(now().minusDays(90)));
 }
 private record Source(LocalDateTime cutoff) implements KeysetPages.Source<Map<String,Object>>{
  public long count(JdbcTemplate db,UUID owner){return db.queryForObject("SELECT COUNT(*) FROM storage_request_body WHERE user_id=? AND received_at>?",Long.class,bytes(owner),Timestamp.valueOf(cutoff));}
  public List<KeysetPages.Entry<Map<String,Object>>> fetch(JdbcTemplate db,UUID owner,PageCursor.Tuple after,int maximum){
   var args=new ArrayList<Object>();args.add(bytes(owner));args.add(Timestamp.valueOf(cutoff));String suffix="";
   if(after!=null){var time=Timestamp.valueOf(LocalDateTime.parse(after.values().getFirst()));suffix=" AND (received_at<? OR (received_at=? AND id<?))";args.add(time);args.add(time);args.add(bytes(after.id()));}args.add(maximum);
   return db.query("SELECT * FROM storage_request_body WHERE user_id=? AND received_at>?"+suffix+" ORDER BY received_at DESC,id DESC LIMIT ?",(r,n)->new KeysetPages.Entry<>(wire(r),new PageCursor.Tuple(List.of(r.getTimestamp("received_at").toLocalDateTime().toString()),uuid(r.getBytes("id")))),args.toArray());
  }
  public Comparator<PageCursor.Tuple> order(){return Comparator.comparing((PageCursor.Tuple p)->p.values().getFirst()).thenComparing(p->p.id().toString()).reversed();}
 }
 private void mark(UUID owner,UUID id,String operation,LocalDateTime at){db.update("INSERT INTO storage_request_operation VALUES(?,?,?,?)",bytes(owner),bytes(parse(operation)),bytes(id),Timestamp.valueOf(at));}
 public void pruneExpired(){
  var cutoff=Timestamp.valueOf(now().minusDays(90));db.update("DELETE FROM storage_request_body WHERE received_at<=?",cutoff);
  for(var row:db.queryForList("SELECT user_id,op_id FROM storage_request_operation WHERE received_at<=? LIMIT 1000",cutoff)){
   db.update("DELETE FROM mutation_receipt WHERE user_id=? AND op_id=?",row.get("user_id"),row.get("op_id"));
   db.update("DELETE FROM storage_request_operation WHERE user_id=? AND op_id=?",row.get("user_id"),row.get("op_id"));
  }
 }
 private LocalDateTime now(){return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);}
 private static LocalDateTime time(Object value){if(value instanceof Timestamp t)return t.toLocalDateTime();if(value instanceof LocalDateTime t)return t;throw new IllegalStateException("Invalid receipt timestamp");}
 private boolean expired(LocalDateTime at){return !at.plusDays(90).isAfter(now());}
 private static void requireOwner(Map<String,Object> row,UUID owner){if(!Arrays.equals((byte[])row.get("user_id"),bytes(owner)))throw missing();}
 private static Map<String,Object> wire(ResultSet r)throws SQLException{
  var at=java.time.format.DateTimeFormatter.ISO_INSTANT.format(r.getTimestamp("received_at").toLocalDateTime().toInstant(ZoneOffset.UTC));var types=new ArrayList<String>();if(r.getBoolean("pin_limit"))types.add("PIN_LIMIT");if(r.getBoolean("storage_quota"))types.add("STORAGE_QUOTA");
  return Map.of("id",uuid(r.getBytes("id")).toString(),"types",types,"status","RECEIVED","revision",1,"received_at",at,"updated_at",at);
 }
 private static IdempotentMutations.Reply reply(int status,Map<String,Object> value){return new IdempotentMutations.Reply(status,JSON.writeValueAsString(value));}
 private static UUID parse(String s){try{UUID id=UUID.fromString(s);if(!id.toString().equals(s))throw invalid();return id;}catch(IllegalArgumentException|NullPointerException e){throw invalid();}}
 private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"INVALID_REQUEST_TYPES","요청 종류와 식별자를 확인해 주세요.",false,Map.of());}
 private static ApiException missing(){return new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청을 찾을 수 없습니다.",false,Map.of());}
 private static ApiException conflict(String code){return new ApiException(HttpStatus.CONFLICT,code,"요청 번호를 다시 확인해 주세요.",false,Map.of());}
 private static ApiException expired(){return conflict("STORAGE_REQUEST_EXPIRED");}
}
