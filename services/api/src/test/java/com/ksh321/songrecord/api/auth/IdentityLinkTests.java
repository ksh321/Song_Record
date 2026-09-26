package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import static org.assertj.core.api.Assertions.*;

class IdentityLinkTests {
    java.sql.Connection keeper;
    JdbcTemplate jdbc;
    SessionService sessions;
    AccountRegistrationService registration;
    AccountRegistrationService.Registration account;
    SessionService.Tokens tokens;
    IdentityLinkService links;
    SessionServiceTests.MutableClock clock;
    @BeforeEach void setup() throws Exception {
        var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;LOCK_TIMEOUT=5000","sa","");
        keeper=ds.getConnection();
        new ResourceDatabasePopulator(new ClassPathResource("registration-schema.sql"),new ClassPathResource("session-schema.sql"),
            new ClassPathResource("link-schema.sql")).populate(keeper);
        jdbc=new JdbcTemplate(ds);var tx=new DataSourceTransactionManager(ds);clock=new SessionServiceTests.MutableClock();
        registration=new AccountRegistrationService(jdbc,tx,clock);
        account=registration.register(new VerifiedProviderIdentity("GOOGLE","g1"),null,"phone");
        sessions=new SessionService(jdbc,tx,clock,Duration.ofMinutes(15),Duration.ofDays(30));tokens=sessions.issue(account);
        links=new IdentityLinkService(jdbc,tx,sessions,(provider,proof,nonce,started)->new VerifiedProviderIdentity(provider,proof),clock);
    }
    @AfterEach void close() throws Exception {keeper.close();}
    IdentityLinkService.Challenge begin() {return links.begin(tokens.accessToken(),account.deviceId(),"GOOGLE","KAKAO");}
    IdentityLinkService.Challenge reauth() {return links.reauthenticate(tokens.accessToken(),account.deviceId(),UUID.fromString(begin().challengeId()),"g1");}
    void finish(IdentityLinkService.Challenge c,String proof){links.link(tokens.accessToken(),account.deviceId(),UUID.fromString(c.challengeId()),proof);}
    void rejects(String code,Runnable fn){assertThatThrownBy(fn::run).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo(code));}
    @Test void linksAndBothLoginsResolveSameUserWithoutNewUser() {
        finish(reauth(),"k1");
        assertThat(links.identities(tokens.accessToken(),account.deviceId())).extracting(IdentityLinkService.Identity::provider).containsExactly("GOOGLE","KAKAO");
        assertThat(registration.register(new VerifiedProviderIdentity("KAKAO","k1"),null,"other phone").userId()).isEqualTo(account.userId());
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM app_user",Integer.class)).isEqualTo(1);
    }
    @Test void cannotUseUnlinkedProviderForReauthentication() {
        rejects("REAUTH_IDENTITY_MISMATCH",()->links.begin(tokens.accessToken(),account.deviceId(),"KAKAO","GOOGLE"));
    }
    @Test void wrongExistingIdentityCannotMintLinkChallenge() {
        var c=begin();rejects("REAUTH_IDENTITY_MISMATCH",()->links.reauthenticate(tokens.accessToken(),account.deviceId(),UUID.fromString(c.challengeId()),"someone-else"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM auth_link_challenge WHERE stage='LINK'",Integer.class)).isZero();
    }
    @Test void cannotSkipReauth() {var c=begin();rejects("LINK_CHALLENGE_EXPIRED",()->finish(c,"k1"));}
    @Test void reauthChallengeExpiresAtFiveMinutes() {
        var c=begin();clock.instant=clock.instant.plusSeconds(300);
        rejects("LINK_CHALLENGE_EXPIRED",()->links.reauthenticate(tokens.accessToken(),account.deviceId(),UUID.fromString(c.challengeId()),"g1"));
    }
    @Test void linkChallengeExpiresAtFiveMinutes() {var c=reauth();clock.instant=clock.instant.plusSeconds(300);rejects("LINK_CHALLENGE_EXPIRED",()->finish(c,"k1"));}
    @Test void reauthCannotBeReplayed() {
        var c=begin();links.reauthenticate(tokens.accessToken(),account.deviceId(),UUID.fromString(c.challengeId()),"g1");
        rejects("LINK_CHALLENGE_EXPIRED",()->links.reauthenticate(tokens.accessToken(),account.deviceId(),UUID.fromString(c.challengeId()),"g1"));
    }
    @Test void linkCannotBeReplayed() {var c=reauth();finish(c,"k1");rejects("LINK_CHALLENGE_EXPIRED",()->finish(c,"k1"));}
    @Test void rejectsIdentityOwnedByAnotherUserAndConsumesChallenge() {
        var other=registration.register(new VerifiedProviderIdentity("KAKAO","k1"),null,"other");
        var c=reauth();rejects("IDENTITY_IN_USE",()->finish(c,"k1"));
        rejects("LINK_CHALLENGE_EXPIRED",()->finish(c,"k2"));
        assertThat(registration.register(new VerifiedProviderIdentity("KAKAO","k1"),null,"other").userId()).isEqualTo(other.userId());
        assertThat(links.identities(tokens.accessToken(),account.deviceId())).hasSize(1);
    }
    @Test void sameEmailDoesNotMergeAccounts() {
        registration.register(new VerifiedProviderIdentity("KAKAO","k1"),null,"other");
        jdbc.update("UPDATE auth_identity SET email='same@example.test'");
        var c=reauth();rejects("IDENTITY_IN_USE",()->finish(c,"k1"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM app_user",Integer.class)).isEqualTo(2);
    }
    @Test void boundToSessionEvenWithinSameUser() {
        var c=begin();var other=sessions.issue(account);
        rejects("LINK_CHALLENGE_EXPIRED",()->links.reauthenticate(other.accessToken(),account.deviceId(),UUID.fromString(c.challengeId()),"g1"));
    }
    @Test void rejectsRevokedSession() {
        var c=reauth();jdbc.update("UPDATE auth_session SET revoked_at=created_at");
        rejects("AUTH_INVALID_SESSION",()->finish(c,"k1"));
    }
    @Test void rejectsRevokedDevice() {
        var c=reauth();jdbc.update("UPDATE device SET revoked_at=created_at");
        rejects("AUTH_INVALID_SESSION",()->finish(c,"k1"));
    }
    @Test void rejectsDeletingUser() {
        var c=reauth();jdbc.update("UPDATE app_user SET status='DELETING'");
        rejects("AUTH_INVALID_SESSION",()->finish(c,"k1"));
    }
    @Test void newFlowInvalidatesOldFlowAndGeneratesNewNonce() {
        var old=begin();var next=begin();assertThat(next.nonce()).isNotEqualTo(old.nonce());
        rejects("LINK_CHALLENGE_EXPIRED",()->links.reauthenticate(tokens.accessToken(),account.deviceId(),UUID.fromString(old.challengeId()),"g1"));
        assertThat(jdbc.queryForObject("SELECT nonce_hash FROM auth_link_challenge",byte[].class)).hasSize(32);
        assertThat(next.toString()).doesNotContain(next.nonce());
    }
    @Test void concurrentConsumptionHasExactlyOneWinner() throws Exception {
        var c=reauth();var gate=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            Callable<Boolean> task=()->{gate.await();try{finish(c,"k1");return true;}catch(ApiException e){return false;}};
            var a=pool.submit(task);var b=pool.submit(task);gate.countDown();
            assertThat(List.of(a.get(10,TimeUnit.SECONDS),b.get(10,TimeUnit.SECONDS))).containsExactlyInAnyOrder(true,false);
        }
    }

    @Test void twoUsersCannotClaimSameNewIdentity() throws Exception {
        var other=registration.register(new VerifiedProviderIdentity("GOOGLE","g2"),null,"other");
        var ot=sessions.issue(other);var oc=links.begin(ot.accessToken(),other.deviceId(),"GOOGLE","KAKAO");
        var ready=links.reauthenticate(ot.accessToken(),other.deviceId(),UUID.fromString(oc.challengeId()),"g2");
        var mine=reauth();var gate=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var a=pool.submit(()->{gate.await();try{finish(mine,"shared");return "OK";}catch(ApiException e){return e.code();}});
            var b=pool.submit(()->{gate.await();try{links.link(ot.accessToken(),other.deviceId(),UUID.fromString(ready.challengeId()),"shared");return "OK";}catch(ApiException e){return e.code();}});
            gate.countDown();
            assertThat(List.of(a.get(10,TimeUnit.SECONDS),b.get(10,TimeUnit.SECONDS))).containsExactlyInAnyOrder("OK","IDENTITY_IN_USE");
        }
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM auth_identity WHERE provider='KAKAO'",Integer.class)).isEqualTo(1);
    }

    UUID identity(String provider) {
        return UUID.fromString(links.identities(tokens.accessToken(),account.deviceId()).stream()
                .filter(i->i.provider().equals(provider)).findFirst().orElseThrow().id());
    }
    @Test void cannotRemoveLastIdentity() {
        rejects("LAST_IDENTITY_REQUIRED",()->links.unlink(tokens.accessToken(),account.deviceId(),identity("GOOGLE")));
        assertThat(links.identities(tokens.accessToken(),account.deviceId())).hasSize(1);
    }
    @Test void unlinkRetainsAccountSessionAndRemainingLogin() {
        finish(reauth(),"k1");
        links.unlink(tokens.accessToken(),account.deviceId(),identity("GOOGLE"));
        assertThat(sessions.authenticate(tokens.accessToken(),account.deviceId()).userId()).isEqualTo(account.userId());
        assertThat(registration.register(new VerifiedProviderIdentity("KAKAO","k1"),null,"other").userId()).isEqualTo(account.userId());
        assertThat(links.identities(tokens.accessToken(),account.deviceId())).extracting(IdentityLinkService.Identity::provider).containsExactly("KAKAO");
    }
    @Test void cannotUnlinkAnotherUserIdentity() {
        var other=registration.register(new VerifiedProviderIdentity("KAKAO","other"),null,"other");
        var otherTokens=sessions.issue(other);
        UUID id=UUID.fromString(links.identities(otherTokens.accessToken(),other.deviceId()).getFirst().id());
        rejects("IDENTITY_NOT_FOUND",()->links.unlink(tokens.accessToken(),account.deviceId(),id));
    }
    @Test void unlinkCancelsOutstandingChallenges() {
        finish(reauth(),"k1");
        links.unlink(tokens.accessToken(),account.deviceId(),identity("KAKAO"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM auth_link_challenge",Integer.class)).isZero();
    }
    @Test void simultaneousUnlinksLeaveExactlyOneMethod() throws Exception {
        finish(reauth(),"k1");
        var google=identity("GOOGLE");var kakao=identity("KAKAO");var gate=new CountDownLatch(1);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var results=new ArrayList<Future<Boolean>>();
            for(var id:List.of(google,kakao)) results.add(pool.submit(()->{
                gate.await();
                try {links.unlink(tokens.accessToken(),account.deviceId(),id);return true;}
                catch(ApiException e){assertThat(e.code()).isEqualTo("LAST_IDENTITY_REQUIRED");return false;}
            }));
            gate.countDown();
            int successes=0;for(var result:results)if(result.get(10,TimeUnit.SECONDS))successes++;
            assertThat(successes).isEqualTo(1);
            assertThat(links.identities(tokens.accessToken(),account.deviceId())).hasSize(1);
        }
    }
    @Test void logoutRevokesAccessAndRefreshButNotOtherDevice() {
        var other=registration.register(new VerifiedProviderIdentity("GOOGLE","g1"),null,"second");
        var otherTokens=sessions.issue(other);
        sessions.logout(tokens.refreshToken(),account.deviceId());
        rejects("AUTH_INVALID_SESSION",()->sessions.authenticate(tokens.accessToken(),account.deviceId()));
        rejects("AUTH_INVALID_SESSION",()->sessions.refresh(tokens.refreshToken(),account.deviceId()));
        assertThat(sessions.authenticate(otherTokens.accessToken(),other.deviceId()).userId()).isEqualTo(account.userId());
    }
    @Test void logoutIsIdempotentAndWorksAfterAccessExpires() {
        clock.instant=clock.instant.plusSeconds(1000);
        sessions.logout(tokens.refreshToken(),account.deviceId());
        sessions.logout(tokens.refreshToken(),account.deviceId());
        rejects("AUTH_INVALID_SESSION",()->sessions.refresh(tokens.refreshToken(),account.deviceId()));
    }
    @Test void logoutRequiresCorrectDevice() {
        rejects("AUTH_INVALID_SESSION",()->sessions.logout(tokens.refreshToken(),UUID.randomUUID()));
        assertThat(sessions.authenticate(tokens.accessToken(),account.deviceId())).isNotNull();
    }
    @Test void logoutWithConsumedProofRevokesRotatedTokens() {
        var rotated=sessions.refresh(tokens.refreshToken(),account.deviceId());
        sessions.logout(tokens.refreshToken(),account.deviceId());
        rejects("AUTH_INVALID_SESSION",()->sessions.authenticate(rotated.accessToken(),account.deviceId()));
        rejects("AUTH_INVALID_SESSION",()->sessions.refresh(rotated.refreshToken(),account.deviceId()));
    }
}
