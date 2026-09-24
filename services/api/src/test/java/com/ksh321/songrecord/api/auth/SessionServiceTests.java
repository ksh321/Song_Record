package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.UUID;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

class SessionServiceTests {
    private java.sql.Connection keeper;
    private JdbcTemplate jdbc;
    private SessionService sessions;
    private AccountRegistrationService registrations;
    private AccountRegistrationService.Registration account;
    private DataSourceTransactionManager manager;
    private MutableClock clock;
    static class MutableClock extends Clock {
        Instant instant=Instant.parse("2026-09-24T00:00:00Z");
        public ZoneId getZone() {return ZoneOffset.UTC;}
        public Clock withZone(ZoneId zone) {return this;}
        public Instant instant() {return instant;}
    }
    @BeforeEach void setup() throws Exception {
        var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;LOCK_TIMEOUT=5000","sa","");
        keeper=ds.getConnection();
        new ResourceDatabasePopulator(new ClassPathResource("registration-schema.sql"),new ClassPathResource("session-schema.sql")).populate(keeper);
        jdbc=new JdbcTemplate(ds);manager=new DataSourceTransactionManager(ds);clock=new MutableClock();
        registrations=new AccountRegistrationService(jdbc,manager,clock);
        account=registrations.register(new VerifiedProviderIdentity("KAKAO","123"),null,"phone");
        sessions=new SessionService(jdbc,manager,clock,Duration.ofMinutes(15),Duration.ofDays(30));
    }
    @AfterEach void close() throws Exception {keeper.close();}
    private void invalid(Runnable action) {assertThatThrownBy(action::run).isInstanceOf(ApiException.class);}
    @Test void issueAuthenticateAndHashOnlyStorage() {
        var tokens=sessions.issue(account);
        assertThat(sessions.authenticate(tokens.accessToken(),account.deviceId()).userId()).isEqualTo(account.userId());
        assertThat(tokens.accessExpiresAt()).isEqualTo(LocalDateTime.of(2026,9,24,0,15));
        assertThat(tokens.refreshExpiresAt()).isEqualTo(LocalDateTime.of(2026,10,24,0,0));
        assertThat(jdbc.queryForObject("SELECT refresh_hash FROM auth_session",byte[].class)).hasSize(32);
        assertThat(tokens.toString()).doesNotContain(tokens.accessToken(),tokens.refreshToken());
    }
    @Test void refreshRotatesWithoutExtendingAbsoluteDeadline() {
        var first=sessions.issue(account);clock.instant=clock.instant.plus(Duration.ofDays(1));
        var second=sessions.refresh(first.refreshToken(),account.deviceId());
        assertThat(second.refreshToken()).isNotEqualTo(first.refreshToken());
        assertThat(second.accessToken()).isNotEqualTo(first.accessToken());
        assertThat(second.refreshExpiresAt()).isEqualTo(first.refreshExpiresAt());
        assertThat(sessions.authenticate(second.accessToken(),account.deviceId()).userId()).isEqualTo(account.userId());
    }
    @Test void replayCommitsRevocationAndInvalidatesAllAccess() {
        var first=sessions.issue(account);var second=sessions.refresh(first.refreshToken(),account.deviceId());
        assertThatThrownBy(()->sessions.refresh(first.refreshToken(),account.deviceId()))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("AUTH_REFRESH_REUSED"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM auth_session WHERE revoked_at IS NOT NULL",Integer.class)).isEqualTo(1);
        invalid(()->sessions.authenticate(first.accessToken(),account.deviceId()));
        invalid(()->sessions.authenticate(second.accessToken(),account.deviceId()));
        invalid(()->sessions.refresh(second.refreshToken(),account.deviceId()));
    }
    @Test void replayDoesNotRevokeOtherSession() {
        var one=sessions.issue(account);var other=sessions.issue(account);
        sessions.refresh(one.refreshToken(),account.deviceId());invalid(()->sessions.refresh(one.refreshToken(),account.deviceId()));
        assertThat(sessions.authenticate(other.accessToken(),account.deviceId())).isNotNull();
    }
    @Test void rejectsWrongDeviceWithoutRevokingValidSession() {
        var tokens=sessions.issue(account);
        invalid(()->sessions.authenticate(tokens.accessToken(),UUID.randomUUID()));
        invalid(()->sessions.refresh(tokens.refreshToken(),UUID.randomUUID()));
        assertThat(sessions.refresh(tokens.refreshToken(),account.deviceId())).isNotNull();
    }
    @Test void rejectsTokenTypeConfusionAndMalformedTokens() {
        var tokens=sessions.issue(account);
        invalid(()->sessions.authenticate(tokens.refreshToken(),account.deviceId()));
        invalid(()->sessions.refresh(tokens.accessToken(),account.deviceId()));
        for(String bad:new String[]{null,"","x".repeat(10000),"sr_a_"+"a".repeat(43)}) invalid(()->sessions.authenticate(bad,account.deviceId()));
    }
    @Test void accessExpiryBoundaryIsRejectedButRefreshWorks() {
        var tokens=sessions.issue(account);clock.instant=clock.instant.plus(Duration.ofMinutes(15));
        invalid(()->sessions.authenticate(tokens.accessToken(),account.deviceId()));
        assertThat(sessions.refresh(tokens.refreshToken(),account.deviceId())).isNotNull();
    }
    @Test void refreshExpiryBoundaryIsRejected() {
        var tokens=sessions.issue(account);clock.instant=clock.instant.plus(Duration.ofDays(30));
        invalid(()->sessions.refresh(tokens.refreshToken(),account.deviceId()));
        invalid(()->sessions.authenticate(tokens.accessToken(),account.deviceId()));
    }
    @Test void deletingAccountBlocksIssueRefreshAndAccess() {
        var tokens=sessions.issue(account);jdbc.update("UPDATE app_user SET status='DELETING'");
        invalid(()->sessions.issue(account));invalid(()->sessions.refresh(tokens.refreshToken(),account.deviceId()));
        invalid(()->sessions.authenticate(tokens.accessToken(),account.deviceId()));
    }
    @Test void revokedDeviceBlocksIssueRefreshAndAccess() {
        var tokens=sessions.issue(account);jdbc.update("UPDATE device SET revoked_at=CURRENT_TIMESTAMP");
        invalid(()->sessions.issue(account));invalid(()->sessions.refresh(tokens.refreshToken(),account.deviceId()));
        invalid(()->sessions.authenticate(tokens.accessToken(),account.deviceId()));
    }
    @Test void foreignOwnershipCannotIssue() {
        var other=registrations.register(new VerifiedProviderIdentity("GOOGLE","other"),null,"other");
        invalid(()->sessions.issue(new AccountRegistrationService.Registration(account.userId(),other.deviceId(),false)));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM auth_session",Integer.class)).isZero();
    }
    @Test void failedRotationRollsBackConsumptionAndCurrentHash() {
        var tokens=sessions.issue(account);
        jdbc.execute("ALTER TABLE auth_access_token ADD CONSTRAINT injected_failure CHECK(created_at < TIMESTAMP '2026-09-24 00:01:00')");
        clock.instant=clock.instant.plusSeconds(60);
        assertThatThrownBy(()->sessions.refresh(tokens.refreshToken(),account.deviceId())).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM auth_refresh_token WHERE consumed_at IS NOT NULL",Integer.class)).isZero();
        jdbc.execute("ALTER TABLE auth_access_token DROP CONSTRAINT injected_failure");
        assertThat(sessions.refresh(tokens.refreshToken(),account.deviceId())).isNotNull();
    }
    @Test void simultaneousRefreshDetectsReuse() throws Exception {
        var tokens=sessions.issue(account);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var start=new CountDownLatch(1);
            Callable<Boolean> action=()->{start.await();try {sessions.refresh(tokens.refreshToken(),account.deviceId());return true;}catch(ApiException e){assertThat(e.code()).isEqualTo("AUTH_REFRESH_REUSED");return false;}};
            var a=pool.submit(action);var b=pool.submit(action);start.countDown();
            assertThat(a.get(15,TimeUnit.SECONDS)).isNotEqualTo(b.get(15,TimeUnit.SECONDS));
            invalid(()->sessions.authenticate(tokens.accessToken(),account.deviceId()));
        }
    }
    @Test void outerTransactionCannotUndoReplayRevocation() {
        assertThatThrownBy(()->new TransactionTemplate(manager).execute(s->sessions.issue(account))).isInstanceOf(IllegalStateException.class);
    }
    @Test void rejectsInvalidTtl() {
        assertThatThrownBy(()->new SessionService(jdbc,manager,clock,Duration.ZERO,Duration.ofDays(30))).isInstanceOf(IllegalArgumentException.class);
    }
}
