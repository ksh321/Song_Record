package com.ksh321.songrecord.api.auth;
import com.ksh321.songrecord.api.account.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;

class DeletionWebOwnershipTests {
 final AccountDeletionTests f=new AccountDeletionTests();DeletionWebOwnership web;
 @BeforeEach void open()throws Exception{
  f.open();String ddl=Files.readString(Path.of("src/main/resources/db/migration/V26__deletion_web_owner_challenges.sql")).replace(" ENGINE=InnoDB","");
  ddl=String.join("\n",ddl.lines().filter(x->!x.strip().startsWith("KEY ix_")).toList());
  new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ByteArrayResource(ddl.getBytes(java.nio.charset.StandardCharsets.UTF_8))).populate(f.f.keeper);
  web=create(Map.of("GOOGLE","synthetic-google-web","KAKAO","synthetic-kakao-web"));
 }
 DeletionWebOwnership create(Map<String,String> clients){return new DeletionWebOwnership(f.f.jdbc,new AccountRegistrationService(f.f.jdbc,f.f.manager,f.f.clock),f.f.sessions,f.service,(provider,proof,nonce,at)->{
  assertThat(nonce).hasSize(32);if("SIGNED_A".equals(proof))return new VerifiedProviderIdentity(provider,"a");if("SIGNED_B".equals(proof))return new VerifiedProviderIdentity(provider,"b");if("SIGNED_UNKNOWN".equals(proof))return new VerifiedProviderIdentity(provider,"unknown-subject");throw new ApiException(org.springframework.http.HttpStatus.UNAUTHORIZED,"INVALID_PROOF","확인 실패",false,Map.of());
 },f.f.clock,"test-rate-secret-not-a-credential-32",clients,f.f.manager);}
 @AfterEach void close()throws Exception{f.close();}
 @Test void verifiedExistingOwnerUsesSameAcceptanceServiceAndOriginalAppSessionsAreRevoked(){
  var c=web.challenge("GOOGLE","127.0.0.1");var p=web.prepare((String)c.get("challenge_id"),"SIGNED_A");
  assertThat(p.get("user_id")).isEqualTo(f.f.registration.userId().toString());f.f.access.revalidate(f.f.account);
  String id=(String)p.get("preparation_id"),token=(String)p.get("status_token");
  assertThat(f.service.status(id,token).get("status")).isEqualTo("PREPARED");
  var reply=f.service.accept("Bearer "+p.get("access_token"),(String)p.get("device_id"),UUID.randomUUID().toString(),token,f.body(p));assertThat(reply.status()).isEqualTo(202);
  assertThat(f.service.status(id,token).get("status")).isEqualTo("ACCEPTED");assertThatThrownBy(()->f.f.access.revalidate(f.f.account)).isInstanceOf(ApiException.class);f.f.access.revalidate(f.f.other);
 }
 @Test void emailUnsignedProofUnknownSubjectAndReplayDoNotCreateOrDeleteAccounts(){
  long users=f.f.jdbc.queryForObject("SELECT COUNT(*) FROM app_user",Long.class);
  var c=web.challenge("GOOGLE","127.0.0.1");String id=(String)c.get("challenge_id");
  assertThatThrownBy(()->web.prepare(id,"someone@example.invalid")).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->web.prepare(id,"SIGNED_UNKNOWN")).isInstanceOf(ApiException.class);
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM app_user",Long.class)).isEqualTo(users);
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM account_deletion_status",Long.class)).isZero();
  var fresh=web.challenge("GOOGLE","127.0.0.1");web.prepare((String)fresh.get("challenge_id"),"SIGNED_A");
  assertThatThrownBy(()->web.prepare((String)fresh.get("challenge_id"),"SIGNED_A")).isInstanceOf(ApiException.class);
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Long.class)).isZero();f.f.access.revalidate(f.f.account);
 }
 @Test void providerNonceStateAndExpiryBoundOwnerVerification(){
  var c=web.challenge("KAKAO","127.0.0.1");assertThat(web.kakaoState((String)c.get("state")).get("provider")).isEqualTo("KAKAO");
  assertThatThrownBy(()->web.kakaoState("x".repeat(43))).isInstanceOf(ApiException.class);
  var p=web.prepare((String)c.get("challenge_id"),"SIGNED_B");assertThat(p.get("user_id")).isEqualTo(f.f.other.principal().userId().toString());
  assertThatThrownBy(()->web.kakaoState((String)c.get("state"))).isInstanceOf(ApiException.class);
  var old=web.challenge("GOOGLE","127.0.0.1");f.f.clock.instant=f.f.clock.instant.plusSeconds(300);
  assertThatThrownBy(()->web.prepare((String)old.get("challenge_id"),"SIGNED_A")).isInstanceOf(ApiException.class);
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Long.class)).isZero();
 }
 @Test void unconfiguredEntryFailsClosedAndPersistentAnonymousRateDataExpires(){
  var disabled=create(Map.of());assertThat(disabled.configuration()).containsEntry("enabled",false);
  assertThatThrownBy(()->disabled.challenge("GOOGLE","127.0.0.1")).isInstanceOf(ApiException.class);
  for(int i=0;i<10;i++)web.challenge("GOOGLE","127.0.0.1");
  assertThatThrownBy(()->web.challenge("GOOGLE","127.0.0.1")).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(429));
  f.f.clock.instant=f.f.clock.instant.plusSeconds(600);web.prune();
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_web_challenge",Long.class)).isZero();
  assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_web_rate",Long.class)).isZero();web.challenge("GOOGLE","127.0.0.1");
 }
 @Test void enabledWebEntryRejectsPlainHttpAndServesOnlyReviewedAssetsWithoutCaching()throws Exception{
  var mvc=org.springframework.test.web.servlet.setup.MockMvcBuilders.standaloneSetup(new DeletionWebController(web,null),new DeletionWebPageController()).setControllerAdvice(new com.ksh321.songrecord.api.web.GlobalExceptionHandler()).build();
  var rejected=mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/v1/account/web/configuration")).andReturn().getResponse();assertThat(rejected.getStatus()).isEqualTo(403);assertThat(rejected.getHeader("Cache-Control")).isEqualTo("no-store");
  var configured=mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/v1/account/web/configuration").secure(true)).andReturn().getResponse();assertThat(configured.getStatus()).isEqualTo(200);assertThat(configured.getContentAsString()).doesNotContain("test-rate-secret","client_secret");
  var page=mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/account-deletion")).andReturn().getResponse();assertThat(page.getStatus()).isEqualTo(200);assertThat(page.getHeader("Cache-Control")).isEqualTo("no-store");assertThat(page.getHeader("Content-Security-Policy")).contains("frame-ancestors 'none'","base-uri 'none'");assertThat(page.getContentAsString(java.nio.charset.StandardCharsets.UTF_8)).contains("계정 탈퇴","이메일만으로 삭제하지 않습니다.");
 }
}
