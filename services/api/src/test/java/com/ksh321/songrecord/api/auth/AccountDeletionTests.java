package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.account.AccountDeletion;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class AccountDeletionTests {
 final IdempotencyTests f=new IdempotencyTests();AccountDeletion service;String auth,device;boolean foreign;
 @BeforeEach void open()throws Exception{
  f.setup();new ResourceDatabasePopulator(new ClassPathResource("account-deletion-schema.sql")).populate(f.keeper);
  f.jdbc.execute("CREATE TABLE deletion_ledger(id BINARY(16) PRIMARY KEY,user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),revision BIGINT,purged_at TIMESTAMP(3))");
  f.jdbc.execute("CREATE TABLE job(id BINARY(16) PRIMARY KEY,user_id BINARY(16),type VARCHAR(64),aggregate_id BINARY(16),dedupe_key VARBINARY(255) UNIQUE,payload VARCHAR(1024),state VARCHAR(16),run_after TIMESTAMP(3),created_at TIMESTAMP(3),updated_at TIMESTAMP(3))");
  auth="Bearer "+f.tokens.accessToken();device=f.registration.deviceId().toString();
  service=new AccountDeletion(f.jdbc,f.access,(provider,proof,nonce,at)->{
   if(!"verified-provider-proof".equals(proof))throw new ApiException(org.springframework.http.HttpStatus.UNAUTHORIZED,"AUTH_INVALID_PROOF","인증 실패",false,Map.of());
   assertThat(nonce).hasSize(32);assertThat(at).isEqualTo(f.clock.instant());
   return new VerifiedProviderIdentity(provider,foreign?"another-subject":"a");
  },f.mutations,f.manager,f.clock);
 }
 @AfterEach void close()throws Exception{f.close();}
 Map<String,Object> prepare(){var c=service.challenge(auth,device,"GOOGLE");return service.prepare(auth,device,(String)c.get("challenge_id"),"verified-provider-proof");}
 String body(Map<String,Object> p){return "{\"preparation_id\":\""+p.get("preparation_id")+"\",\"base_revision\":"+p.get("base_revision")+",\"reauth_proof\":\""+p.get("reauth_proof")+"\",\"scope\":\"ALL_ACCOUNT_DATA\",\"confirmed\":true}";}
 @Test void preparationDoesNotDeleteAndAcceptanceAtomicallyBlocksAllSessionsRegistersJobAndLedger(){
  var second=f.sessions.issue(f.registration);var p=prepare();String id=(String)p.get("preparation_id"),token=(String)p.get("status_token");
  assertThat(service.status(id,token).get("status")).isEqualTo("PREPARED");f.access.revalidate(f.account);
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isZero();
  var result=service.accept(auth,device,UUID.randomUUID().toString(),token,body(p));assertThat(result.status()).isEqualTo(202);
  assertThat(service.status(id,token)).containsEntry("status","ACCEPTED").doesNotContainKeys("user_id","email","object_key","operation_id","token_hash");
  assertThatThrownBy(()->f.sessions.authenticate(f.tokens.accessToken(),f.registration.deviceId())).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->f.sessions.authenticate(second.accessToken(),f.registration.deviceId())).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->f.sessions.refresh(second.refreshToken(),f.registration.deviceId())).isInstanceOf(ApiException.class);
  f.access.revalidate(f.other);
  assertThat(f.jdbc.queryForObject("SELECT status FROM app_user WHERE id=?",String.class,bytes(f.registration.userId()))).isEqualTo("DELETING");
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job WHERE type='ACCOUNT_DELETE' AND state='QUEUED'",Integer.class)).isEqualTo(1);
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger WHERE entity_type='USER'",Integer.class)).isEqualTo(1);
  assertThat(f.jdbc.queryForObject("SELECT response_body FROM mutation_receipt",String.class)).doesNotContain(token);
  assertThatThrownBy(()->service.accept(auth,device,UUID.randomUUID().toString(),token,body(p))).isInstanceOf(ApiException.class);
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isEqualTo(1);
 }
 @Test void scopeConsentRevisionTokenAndWrongProviderIdentityNeverDelete(){
  var p=prepare();String token=(String)p.get("status_token");
  for(var invalid:List.of(body(p).replace("true","false"),body(p).replace("ALL_ACCOUNT_DATA","EMAIL_ONLY"),body(p).replace("\"base_revision\":1","\"base_revision\":2"),body(p).replace("}",",\"user_id\":\"arbitrary\"}"))){assertThatThrownBy(()->service.accept(auth,device,UUID.randomUUID().toString(),token,invalid)).isInstanceOf(ApiException.class);}
  assertThatThrownBy(()->service.accept(auth,device,UUID.randomUUID().toString(),"b".repeat(43),body(p))).isInstanceOf(ApiException.class);
  var c=service.challenge(auth,device,"GOOGLE");foreign=true;
  assertThatThrownBy(()->service.prepare(auth,device,(String)c.get("challenge_id"),"verified-provider-proof")).isInstanceOf(ApiException.class);
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Integer.class)).isZero();
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();f.access.revalidate(f.account);
 }
 @Test void expiredRecentProofCannotAcceptButSavedTokenResolvesLostReplyAndThirtyDayExpiry(){
  var p=prepare();String token=(String)p.get("status_token"),id=(String)p.get("preparation_id");
  f.clock.instant=f.clock.instant.plusSeconds(301);
  assertThatThrownBy(()->service.accept(auth,device,UUID.randomUUID().toString(),token,body(p))).isInstanceOf(ApiException.class);f.access.revalidate(f.account);
  f.clock.instant=f.clock.instant.minusSeconds(301);
  service.accept(auth,device,UUID.randomUUID().toString(),token,body(p));
  var recreated=new AccountDeletion(f.jdbc,f.access,(a,b,c,d)->{throw new AssertionError("No identity call for restricted status");},f.mutations,f.manager,f.clock);
  assertThat(recreated.status(id,token).get("status")).isEqualTo("ACCEPTED");
  f.clock.instant=f.clock.instant.plus(Duration.ofDays(30));
  assertThatThrownBy(()->recreated.status(id,token)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(410));
  assertThatThrownBy(()->recreated.status(id,"c".repeat(43))).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(404));
 }
 @Test void jobFailureRollsBackStatusRevocationLedgerAndReceipt(){
  var p=prepare();f.jdbc.execute("DROP TABLE job");
  assertThatThrownBy(()->service.accept(auth,device,UUID.randomUUID().toString(),(String)p.get("status_token"),body(p))).isInstanceOf(org.springframework.dao.DataAccessException.class);
  assertThat(service.status((String)p.get("preparation_id"),(String)p.get("status_token")).get("status")).isEqualTo("PREPARED");f.access.revalidate(f.account);
  assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_ledger",Integer.class)).isZero();assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM mutation_receipt",Integer.class)).isZero();
 }
 @Test void restrictedStatusHasNoAccountLookupAndPersistsRateWindowAcrossServiceRestart(){
  var p=prepare();String id=(String)p.get("preparation_id"),token=(String)p.get("status_token");
  assertThatThrownBy(()->service.status("not-an-id",token)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(404));
  for(int i=0;i<60;i++)assertThat(service.status(id,token).get("status")).isEqualTo("PREPARED");
  var restarted=new AccountDeletion(f.jdbc,f.access,(a,b,c,d)->{throw new AssertionError("No identity exchange during status");},f.mutations,f.manager,f.clock);
  assertThatThrownBy(()->restarted.status(id,token)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(429));
  f.clock.instant=f.clock.instant.plusSeconds(60);
  assertThat(restarted.status(id,token).get("status")).isEqualTo("PREPARED");
 }
}
