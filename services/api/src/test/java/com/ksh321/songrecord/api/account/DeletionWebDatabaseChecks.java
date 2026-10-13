package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static org.assertj.core.api.Assertions.*;
public final class DeletionWebDatabaseChecks {
 private DeletionWebDatabaseChecks(){}
 public static void verify(JdbcTemplate db){
  var tx=new DataSourceTransactionManager(db.getDataSource());var clock=Clock.fixed(Instant.parse("2026-10-12T00:00:00Z"),ZoneOffset.UTC);
  var identity=new VerifiedProviderIdentity("GOOGLE","web-owner-test-"+UUID.randomUUID());
  var registrations=new AccountRegistrationService(db,tx,clock);var original=registrations.register(identity,null,"isolated web test");
  var sessions=new SessionService(db,tx,clock,Duration.ofMinutes(15),Duration.ofDays(30));var originalTokens=sessions.issue(original);
  var access=new AccountAccess(sessions);var mutations=new IdempotentMutations(db,access,tx,clock);
  var deletion=new AccountDeletion(db,access,(a,b,c,d)->identity,mutations,tx,clock);
  var web=new DeletionWebOwnership(db,registrations,sessions,deletion,(a,b,c,d)->identity,clock,"test-only-rate-pepper-not-a-credential",Map.of("GOOGLE","synthetic-client"),tx);
  var c=web.challenge("GOOGLE","127.0.0.1");var p=web.prepare((String)c.get("challenge_id"),"synthetic proof verifier boundary");
  assertThat(p.get("user_id")).isEqualTo(original.userId().toString());
  assertThatThrownBy(()->web.prepare((String)c.get("challenge_id"),"same proof")).isInstanceOf(ApiException.class);
  String id=(String)p.get("preparation_id"),token=(String)p.get("status_token");
  String body="{\"preparation_id\":\""+id+"\",\"base_revision\":1,\"reauth_proof\":\""+p.get("reauth_proof")+"\",\"scope\":\"ALL_ACCOUNT_DATA\",\"confirmed\":true}";
  assertThat(deletion.accept("Bearer "+p.get("access_token"),(String)p.get("device_id"),UUID.randomUUID().toString(),token,body).status()).isEqualTo(202);
  assertThat(deletion.status(id,token).get("status")).isEqualTo("ACCEPTED");
  assertThatThrownBy(()->sessions.authenticate(originalTokens.accessToken(),original.deviceId())).isInstanceOf(ApiException.class);
  long before=db.queryForObject("SELECT COUNT(*) FROM app_user",Long.class);
  assertThatThrownBy(()->registrations.registerExisting(new VerifiedProviderIdentity("GOOGLE","unknown-web-"+UUID.randomUUID()),"no signup")).isInstanceOf(ApiException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM app_user",Long.class)).isEqualTo(before);
 }
}
