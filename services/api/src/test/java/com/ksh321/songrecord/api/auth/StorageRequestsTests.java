package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.account.*;
import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.util.LinkedMultiValueMap;
import static org.assertj.core.api.Assertions.*;

class StorageRequestsTests {
 final PinSlotsTests f=new PinSlotsTests();StorageRequests requests;
 @BeforeEach void open()throws Exception{
  f.open();var db=f.f.jdbc;
  db.execute("CREATE TABLE storage_request_ledger(id BINARY(16) PRIMARY KEY,user_id BINARY(16),received_at TIMESTAMP(3))");
  db.execute("CREATE TABLE storage_request_body(id BINARY(16) PRIMARY KEY,user_id BINARY(16),pin_limit BOOLEAN,storage_quota BOOLEAN,received_at TIMESTAMP(3),revision BIGINT DEFAULT 1,pinned_used INT,pinned_limit INT,used_bytes BIGINT,quota_bytes BIGINT)");
  db.execute("CREATE TABLE storage_request_operation(user_id BINARY(16),op_id BINARY(16),request_id BINARY(16),received_at TIMESTAMP(3),PRIMARY KEY(user_id,op_id))");
  db.execute("CREATE TABLE storage_request_daily(period_date DATE PRIMARY KEY,request_total BIGINT,pin_requests BIGINT,quota_requests BIGINT,unique_users BIGINT)");
  var pages=new KeysetPages(db,f.f.access,f.f.manager,new PageCursor(new byte[32],f.f.clock,Duration.ofMinutes(30)));
  requests=new StorageRequests(db,f.f.access,f.f.mutations,pages,f.f.clock);
 }
 @AfterEach void close()throws Exception{f.close();}
 String body(UUID id,String... types){return "{\"id\":\""+id+"\",\"types\":["+String.join(",",Arrays.stream(types).map(t->"\""+t+"\"").toList())+"]}";}
 @Test void repeatsAndLostResponsesCountOncePerSubmissionAndUniqueUserOnce(){
  UUID id=UUID.randomUUID();String op=UUID.randomUUID().toString(),body=body(id,"PIN_LIMIT","STORAGE_QUOTA");
  var first=requests.create(f.auth,f.device,op,body);assertThat(first.status()).isEqualTo(201);
  assertThat(requests.create(f.auth,f.device,op,body)).isEqualTo(first);
  assertThat(requests.create(f.auth,f.device,UUID.randomUUID().toString(),body).status()).isEqualTo(200);
  requests.create(f.auth,f.device,UUID.randomUUID().toString(),body(UUID.randomUUID(),"PIN_LIMIT"));
  var counts=f.f.jdbc.queryForMap("SELECT * FROM storage_request_daily");
  assertThat(((Number)counts.get("request_total")).longValue()).isEqualTo(2);
  assertThat(((Number)counts.get("pin_requests")).longValue()).isEqualTo(2);
  assertThat(((Number)counts.get("quota_requests")).longValue()).isEqualTo(1);
  assertThat(((Number)counts.get("unique_users")).longValue()).isEqualTo(1);
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM pin_slot",Long.class)).isZero();
  assertThat(requests.get(f.auth,f.device,id.toString())).containsEntry("revision",1).doesNotContainKeys("user_id","used_bytes","pinned_limit");
 }
 @Test void changedBodyIdsTypesAndOwnerAreRejected(){
  UUID id=UUID.randomUUID();String op=UUID.randomUUID().toString();requests.create(f.auth,f.device,op,body(id,"PIN_LIMIT"));
  assertCode(()->requests.create(f.auth,f.device,op,body(UUID.randomUUID(),"PIN_LIMIT")),"IDEMPOTENCY_CONFLICT");
  assertCode(()->requests.create(f.auth,f.device,UUID.randomUUID().toString(),body(id,"STORAGE_QUOTA")),"REQUEST_ID_CONFLICT");
  for(String[] types:new String[][]{{},{"PIN_LIMIT","PIN_LIMIT"},{"PAID"}})assertCode(()->requests.create(f.auth,f.device,UUID.randomUUID().toString(),body(UUID.randomUUID(),types)),"INVALID_REQUEST_TYPES");
  var p=f.f.other.principal();String other="Bearer "+f.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false)).accessToken();
  assertCode(()->requests.get(other,p.deviceId().toString(),id.toString()),"RESOURCE_NOT_FOUND");
  assertCode(()->requests.create(other,p.deviceId().toString(),UUID.randomUUID().toString(),body(id,"PIN_LIMIT")),"RESOURCE_NOT_FOUND");
 }
 @Test void expiryPrunesBodyAndOwnReceiptsButPreservesAnonymousCountsAndIdLedger(){
  UUID id=UUID.randomUUID();String op=UUID.randomUUID().toString();requests.create(f.auth,f.device,op,body(id,"PIN_LIMIT"));
  f.f.clock.instant=f.f.clock.instant.plus(Duration.ofDays(90));
  String auth="Bearer "+f.f.sessions.issue(f.f.registration).accessToken();
  assertCode(()->requests.create(auth,f.device,op,body(id,"PIN_LIMIT")),"STORAGE_REQUEST_EXPIRED");
  assertCode(()->requests.get(auth,f.device,id.toString()),"RESOURCE_NOT_FOUND");
  requests.pruneExpired();
  for(String table:List.of("storage_request_body","storage_request_operation","mutation_receipt"))assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Long.class)).isZero();
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM storage_request_ledger",Long.class)).isEqualTo(1);
  assertThat(f.f.jdbc.queryForObject("SELECT request_total FROM storage_request_daily",Long.class)).isEqualTo(1);
  assertCode(()->requests.create(auth,f.device,UUID.randomUUID().toString(),body(id,"PIN_LIMIT")),"STORAGE_REQUEST_EXPIRED");
  assertThat(requests.create(auth,f.device,UUID.randomUUID().toString(),body(UUID.randomUUID(),"PIN_LIMIT")).status()).isEqualTo(201);
 }
 @Test void recentListUsesDescendingStableCursorAndRejectsUnknownQuery(){
  for(int n=0;n<3;n++)requests.create(f.auth,f.device,UUID.randomUUID().toString(),body(UUID.randomUUID(),"STORAGE_QUOTA"));
  var query=new LinkedMultiValueMap<String,String>();query.add("limit","2");var first=requests.list(f.auth,f.device,query);assertThat(first.items()).hasSize(2);assertThat(first.next_cursor()).isNotNull();
  query.add("cursor",first.next_cursor());var second=requests.list(f.auth,f.device,query);assertThat(second.items()).hasSize(1);
  assertThat(first.items()).doesNotContainAnyElementsOf(second.items());
  query.add("user_id",f.owner.toString());assertCode(()->requests.list(f.auth,f.device,query),"INVALID_REQUEST_TYPES");
 }
 static void assertCode(Runnable work,String code){assertThatThrownBy(work::run).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo(code));}
}
