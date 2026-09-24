package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Internal boundary. Call ONLY after provider proof verification, outside any transaction. */
public final class AccountRegistrationService {
    private final JdbcTemplate jdbc;
    private final AuthIdentityRepository identities;
    private final TransactionTemplate transaction;
    private final Clock clock;

    public AccountRegistrationService(JdbcTemplate jdbc, PlatformTransactionManager manager, Clock clock) {
        this.jdbc = jdbc;
        identities = new JdbcAuthIdentityRepository(jdbc);
        this.clock = clock;
        transaction = new TransactionTemplate(manager);
        transaction.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
        transaction.setTimeout(10);
    }

    /** existingDeviceId is only an account-scoped hint, never authentication proof. */
    public Registration register(VerifiedProviderIdentity verified, UUID existingDeviceId, String displayName) {
        validate(verified, displayName);
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException("Registration must own its transaction for conflict retries");
        }
        // Retry only AFTER the entire failed transaction has rolled back.
        for (int attempt = 0; attempt < 3; attempt++) {
            try {
                return transaction.execute(status -> registerOnce(verified, existingDeviceId, displayName));
            } catch (DuplicateKeyException | PessimisticLockingFailureException conflict) {
                if (attempt == 2) {
                    throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "AUTH_REGISTRATION_BUSY",
                            "로그인 처리가 지연되고 있습니다. 다시 시도해 주세요.", true, Map.of());
                }
            }
        }
        throw new IllegalStateException("Unreachable");
    }

    private Registration registerOnce(VerifiedProviderIdentity verified, UUID existingDeviceId, String name) {
        LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
        var identity = identities.find(verified);
        UUID userId;
        boolean created = identity.isEmpty();
        if (created) {
            userId = UUID.randomUUID();
            jdbc.update("INSERT INTO app_user (id,status,created_at,updated_at) VALUES (?,'ACTIVE',?,?)",
                    bytes(userId), now, now);
            // A concurrent winner causes this unique insert to fail; its losing user rolls back too.
            jdbc.update("INSERT INTO auth_identity (id,user_id,provider,provider_user_id,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                    bytes(UUID.randomUUID()), bytes(userId), verified.provider(), verified.providerUserId(), now, now);
            jdbc.update("INSERT INTO user_sync_state (user_id) VALUES (?)", bytes(userId));
            jdbc.update("INSERT INTO user_entitlement (user_id,plan_code,pinned_limit,quota_bytes) VALUES (?,'FREE',10,1000000000)", bytes(userId));
            jdbc.update("INSERT INTO storage_usage (user_id,used_bytes,reserved_bytes) VALUES (?,0,0)", bytes(userId));
        } else {
            userId = identity.orElseThrow().userId();
            // Serializes device registration and blocks registration after deletion starts.
            String state = jdbc.queryForObject("SELECT status FROM app_user WHERE id = ? FOR UPDATE", String.class, bytes(userId));
            if (!"ACTIVE".equals(state)) {
                throw new ApiException(HttpStatus.FORBIDDEN, "ACCOUNT_UNAVAILABLE",
                        "현재 로그인할 수 없는 계정입니다.", false, Map.of());
            }
        }
        UUID deviceId;
        if (existingDeviceId == null) {
            deviceId = UUID.randomUUID();
            jdbc.update("INSERT INTO device (id,user_id,display_name,last_seen_at,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                    bytes(deviceId), bytes(userId), name, now, now, now);
        } else {
            deviceId = existingDeviceId;
            var devices = jdbc.query("SELECT revoked_at FROM device WHERE user_id = ? AND id = ? FOR UPDATE",
                    (rs, row) -> rs.getObject(1) == null, bytes(userId), bytes(deviceId));
            if (devices.size() != 1 || !devices.getFirst()) {
                throw new ApiException(HttpStatus.CONFLICT, "DEVICE_UNAVAILABLE",
                        "기기를 새로 등록해 주세요.", false, Map.of());
            }
            jdbc.update("UPDATE device SET display_name=?, last_seen_at=?, updated_at=? WHERE user_id=? AND id=?",
                    name, now, now, bytes(userId), bytes(deviceId));
        }
        return new Registration(userId, deviceId, created);
    }

    private static void validate(VerifiedProviderIdentity identity, String name) {
        if (identity == null || !("GOOGLE".equals(identity.provider()) || "KAKAO".equals(identity.provider()))
                || identity.providerUserId() == null || identity.providerUserId().isBlank()
                || identity.providerUserId().codePointCount(0, identity.providerUserId().length()) > 255
                || name == null || name.isBlank() || name.codePointCount(0, name.length()) > 200) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REGISTRATION_INPUT",
                    "로그인 등록 정보를 확인해 주세요.", false, Map.of());
        }
    }

    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }

    public record Registration(UUID userId, UUID deviceId, boolean newUser) {}
}
