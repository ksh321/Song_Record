package com.ksh321.songrecord.api.account;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.idempotency.IdempotentMutations;
import com.ksh321.songrecord.api.retention.RetentionQueries;
import com.ksh321.songrecord.api.uploads.UploadApproval;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static org.assertj.core.api.Assertions.*;

/** Real MySQL and migrated constraints; only newly registered synthetic accounts are affected. */
public final class AccountDeletionDatabaseChecks {
 private AccountDeletionDatabaseChecks(){}
 public static void verify(JdbcTemplate db){
  var tx=new DataSourceTransactionManager(db.getDataSource());var clock=Clock.fixed(Instant.parse("2026-10-12T00:00:00Z"),ZoneOffset.UTC);
  var identity=new VerifiedProviderIdentity("GOOGLE","deletion-check-"+UUID.randomUUID());
  var registration=new AccountRegistrationService(db,tx,clock).register(identity,null,"isolated test");
  var sessions=new SessionService(db,tx,clock,Duration.ofMinutes(15),Duration.ofDays(30));var tokens=sessions.issue(registration);
  var access=new AccountAccess(sessions);var mutations=new IdempotentMutations(db,access,tx,clock);
  var service=new AccountDeletion(db,access,(a,b,c,d)->identity,mutations,tx,clock);
  String auth="Bearer "+tokens.accessToken(),device=registration.deviceId().toString();
  var c=service.challenge(auth,device,"GOOGLE");var p=service.prepare(auth,device,(String)c.get("challenge_id"),"synthetic signed-proof boundary");
  String id=(String)p.get("preparation_id"),token=(String)p.get("status_token");
  String body="{\"preparation_id\":\""+id+"\",\"base_revision\":1,\"reauth_proof\":\""+p.get("reauth_proof")+"\",\"scope\":\"ALL_ACCOUNT_DATA\",\"confirmed\":true}";
  assertThat(service.status(id,token).get("status")).isEqualTo("PREPARED");
  assertThat(service.accept(auth,device,UUID.randomUUID().toString(),token,body).status()).isEqualTo(202);
  assertThat(service.status(id,token).get("status")).isEqualTo("ACCEPTED");
  assertThatThrownBy(()->sessions.authenticate(tokens.accessToken(),registration.deviceId())).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->sessions.refresh(tokens.refreshToken(),registration.deviceId())).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->new RetentionQueries(db,access,tx).storage(auth,device)).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->new com.ksh321.songrecord.api.playback.PlaybackUrls(db,access,tx,(key)->{throw new AssertionError("Signer must not run after deletion acceptance");}).issue(auth,device,UUID.randomUUID())).isInstanceOf(ApiException.class);
  assertThatThrownBy(()->new UploadApproval(db,access,tx,clock,mutations).authorize(auth,device,UUID.randomUUID().toString(),UUID.randomUUID(),"{}" )).isInstanceOf(ApiException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM job WHERE user_id=? AND type='ACCOUNT_DELETE' AND state='QUEUED'",Integer.class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(registration.userId()))).isEqualTo(1);
 }
}
