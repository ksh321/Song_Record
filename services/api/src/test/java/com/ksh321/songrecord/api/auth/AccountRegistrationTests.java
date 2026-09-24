package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;

class AccountRegistrationTests {
    private JdbcTemplate jdbc;
    private java.sql.Connection schemaConnection;
    @org.junit.jupiter.api.AfterEach void closeSchemaConnection() throws Exception { schemaConnection.close(); }
    private AccountRegistrationService service;
    private DataSourceTransactionManager manager;
    private final VerifiedProviderIdentity identity = new VerifiedProviderIdentity("KAKAO", "123");
    @BeforeEach void setup() throws Exception {
        var source = new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID() + ";MODE=MySQL;LOCK_TIMEOUT=5000", "sa", "");
        schemaConnection = source.getConnection();
        new ResourceDatabasePopulator(new ClassPathResource("registration-schema.sql")).populate(schemaConnection);
        jdbc = new JdbcTemplate(source);
        manager = new DataSourceTransactionManager(source);
        service = new AccountRegistrationService(jdbc, manager,
                Clock.fixed(Instant.parse("2026-09-24T00:00:00Z"), ZoneOffset.UTC));
    }
    private int count(String table) { return jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class); }
    private void assertEmpty() {
        for (String table : new String[]{"app_user","auth_identity","device","user_entitlement","storage_usage","user_sync_state"})
            assertThat(count(table)).as(table).isZero();
    }
    @Test void firstLoginCreatesAllRowsWithServerDefaults() {
        var result = service.register(identity, null, "Android");
        assertThat(result.newUser()).isTrue();
        for (String table : new String[]{"app_user","auth_identity","device","user_entitlement","storage_usage","user_sync_state"})
            assertThat(count(table)).as(table).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT pinned_limit FROM user_entitlement", Integer.class)).isEqualTo(10);
        assertThat(jdbc.queryForObject("SELECT quota_bytes FROM user_entitlement", Long.class)).isEqualTo(1000000000L);
        assertThat(jdbc.queryForObject("SELECT used_bytes+reserved_bytes FROM storage_usage", Long.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state", Long.class)).isZero();
    }
    @Test void returningLoginPreservesUsageAndEntitlement() {
        var first = service.register(identity, null, "old");
        jdbc.update("UPDATE storage_usage SET used_bytes=123,reserved_bytes=45");
        jdbc.update("UPDATE user_entitlement SET pinned_limit=20");
        var second = service.register(identity, first.deviceId(), "new");
        assertThat(second.userId()).isEqualTo(first.userId());
        assertThat(second.deviceId()).isEqualTo(first.deviceId());
        assertThat(second.newUser()).isFalse();
        assertThat(count("device")).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT display_name FROM device", String.class)).isEqualTo("new");
        assertThat(jdbc.queryForObject("SELECT used_bytes+reserved_bytes FROM storage_usage", Long.class)).isEqualTo(168);
        assertThat(jdbc.queryForObject("SELECT pinned_limit FROM user_entitlement", Integer.class)).isEqualTo(20);
    }
    @Test void secondDeviceBelongsToSameAccount() {
        var first = service.register(identity, null, "one");
        var second = service.register(identity, null, "two");
        assertThat(second.userId()).isEqualTo(first.userId());
        assertThat(second.deviceId()).isNotEqualTo(first.deviceId());
        assertThat(count("app_user")).isEqualTo(1);
        assertThat(count("device")).isEqualTo(2);
    }
    @Test void sameIdAcrossProvidersDoesNotMergeUsers() {
        var first = service.register(identity, null, "one");
        var second = service.register(new VerifiedProviderIdentity("GOOGLE", "123"), null, "two");
        assertThat(second.userId()).isNotEqualTo(first.userId());
        assertThat(count("app_user")).isEqualTo(2);
    }
    @Test void foreignDeviceRollsBackEntireNewAccount() {
        var first = service.register(identity, null, "one");
        assertThatThrownBy(() -> service.register(new VerifiedProviderIdentity("GOOGLE", "other"), first.deviceId(), "bad"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("DEVICE_UNAVAILABLE"));
        assertThat(count("app_user")).isEqualTo(1);
        assertThat(count("auth_identity")).isEqualTo(1);
        assertThat(count("user_entitlement")).isEqualTo(1);
    }
    @Test void revokedDeviceIsNotReactivated() {
        var first = service.register(identity, null, "one");
        jdbc.update("UPDATE device SET revoked_at=CURRENT_TIMESTAMP");
        assertThatThrownBy(() -> service.register(identity, first.deviceId(), "bad")).isInstanceOf(ApiException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM device WHERE revoked_at IS NOT NULL", Integer.class)).isEqualTo(1);
    }
    @Test void deletingAccountCannotRegisterDevice() {
        service.register(identity, null, "one");
        jdbc.update("UPDATE app_user SET status='DELETING'");
        assertThatThrownBy(() -> service.register(identity, null, "bad"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.code()).isEqualTo("ACCOUNT_UNAVAILABLE"));
        assertThat(count("device")).isEqualTo(1);
    }
    @Test void lastInsertFailureRollsBackEveryInitialRow() {
        jdbc.execute("ALTER TABLE device ADD CONSTRAINT injected_failure CHECK (display_name <> 'fail')");
        assertThatThrownBy(() -> service.register(identity, null, "fail")).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertEmpty();
    }
    @Test void invalidNameWritesNothing() {
        for (String name : new String[]{null,"", " ", "x".repeat(201)})
            assertThatThrownBy(() -> service.register(identity, null, name)).isInstanceOf(ApiException.class);
        assertEmpty();
    }
    @Test void invalidIdentityWritesNothing() {
        for (var bad : new VerifiedProviderIdentity[]{null,new VerifiedProviderIdentity("OTHER","1"),new VerifiedProviderIdentity("KAKAO", " ")})
            assertThatThrownBy(() -> service.register(bad, null, "phone")).isInstanceOf(ApiException.class);
        assertEmpty();
    }
    @Test void refusesOuterTransactionToKeepRetriesSafe() {
        assertThatThrownBy(() -> new TransactionTemplate(manager).execute(s -> service.register(identity, null, "phone")))
                .isInstanceOf(IllegalStateException.class);
        assertEmpty();
    }
    @Test void simultaneousFirstLoginsConvergeOnOneUser() throws Exception {
        try (var pool = Executors.newFixedThreadPool(8)) {
            var start = new CountDownLatch(1);
            var tasks = new ArrayList<java.util.concurrent.Future<AccountRegistrationService.Registration>>();
            for (int i=0; i<8; i++) tasks.add(pool.submit(() -> { start.await(); return service.register(identity, null, "phone"); }));
            start.countDown();
            var results = new ArrayList<AccountRegistrationService.Registration>();
            for (var task : tasks) results.add(task.get(15, TimeUnit.SECONDS));
            assertThat(results.stream().map(AccountRegistrationService.Registration::userId).distinct().count()).isEqualTo(1);
            assertThat(results.stream().filter(AccountRegistrationService.Registration::newUser).count()).isEqualTo(1);
            assertThat(count("app_user")).isEqualTo(1);
            assertThat(count("auth_identity")).isEqualTo(1);
            assertThat(count("user_entitlement")).isEqualTo(1);
            assertThat(count("storage_usage")).isEqualTo(1);
            assertThat(count("user_sync_state")).isEqualTo(1);
            assertThat(count("device")).isEqualTo(8);
        }
    }
}
