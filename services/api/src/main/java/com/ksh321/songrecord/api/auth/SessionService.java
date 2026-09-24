package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Internal session boundary; issuance must follow verified social login and registration. */
public final class SessionService {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;
    private final Clock clock;
    private final Duration accessTtl;
    private final Duration refreshTtl;
    private final SecureRandom random = new SecureRandom();

    public SessionService(JdbcTemplate jdbc, PlatformTransactionManager manager, Clock clock,
                          Duration accessTtl, Duration refreshTtl) {
        if (accessTtl == null || refreshTtl == null || accessTtl.compareTo(Duration.ofSeconds(1)) < 0
                || refreshTtl.compareTo(accessTtl) < 0 || refreshTtl.compareTo(Duration.ofDays(365)) > 0) {
            throw new IllegalArgumentException("Invalid session lifetimes");
        }
        this.jdbc=jdbc; this.clock=clock; this.accessTtl=accessTtl; this.refreshTtl=refreshTtl;
        tx=new TransactionTemplate(manager);
        tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
        tx.setTimeout(10);
    }

    /** Never expose userId/deviceId-only issuance as an HTTP endpoint. */
    public Tokens issue(AccountRegistrationService.Registration registration) {
        ownTransaction();
        if (registration == null) throw invalid();
        return tx.execute(status -> {
            UUID user=registration.userId(), device=registration.deviceId();
            lockOwner(user,device);
            LocalDateTime now=now(), deadline=now.plus(refreshTtl);
            UUID session=UUID.randomUUID();
            String refresh=token("sr_r_");
            jdbc.update("INSERT INTO auth_session(id,user_id,device_id,refresh_hash,expires_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                    bytes(session),bytes(user),bytes(device),hash(refresh),deadline,now,now);
            return storeTokens(session,refresh,now,deadline);
        });
    }

    public Tokens refresh(String refreshToken, UUID deviceId) {
        ownTransaction();
        checkToken(refreshToken,"sr_r_");
        if(deviceId==null) throw invalid();
        Outcome result=tx.execute(status -> {
            var matches=jdbc.query("SELECT s.id,s.user_id,s.device_id FROM auth_refresh_token t JOIN auth_session s ON s.id=t.session_id WHERE t.token_hash=?",
                    (rs,row)->new Principal(uuid(rs.getBytes(2)),uuid(rs.getBytes(3)),uuid(rs.getBytes(1))),hash(refreshToken));
            if(matches.size()!=1 || !deviceId.equals(matches.getFirst().deviceId())) throw invalid();
            Principal owner=matches.getFirst();
            lockOwner(owner.userId(),owner.deviceId());
            var session=jdbc.queryForObject("SELECT refresh_hash,expires_at,revoked_at FROM auth_session WHERE id=? FOR UPDATE",
                    (rs,row)->new SessionRow(rs.getBytes(1),rs.getObject(2,LocalDateTime.class),rs.getObject(3)!=null),bytes(owner.sessionId()));
            LocalDateTime now=now();
            LocalDateTime expiry=session.expiresAt();
            if(session.revoked() || !expiry.isAfter(now)) throw invalid();
            var history=jdbc.queryForMap("SELECT consumed_at FROM auth_refresh_token WHERE token_hash=?",hash(refreshToken));
            if(history.get("consumed_at")!=null || !MessageDigest.isEqual(session.refreshHash(),hash(refreshToken))) {
                jdbc.update("UPDATE auth_session SET revoked_at=?,updated_at=? WHERE id=?",now,now,bytes(owner.sessionId()));
                // Return a marker: throwing here would ROLLBACK the security revocation.
                return new Outcome(null,true);
            }
            String next=token("sr_r_");
            jdbc.update("UPDATE auth_refresh_token SET consumed_at=? WHERE token_hash=?",now,hash(refreshToken));
            jdbc.update("UPDATE auth_session SET refresh_hash=?,updated_at=? WHERE id=?",hash(next),now,bytes(owner.sessionId()));
            return new Outcome(storeTokens(owner.sessionId(),next,now,expiry),false);
        });
        if(result.reused()) throw new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_REFRESH_REUSED",
                "로그인 세션이 종료되었습니다. 다시 로그인해 주세요.",false,Map.of());
        return result.tokens();
    }

    public Principal authenticate(String accessToken, UUID deviceId) {
        checkToken(accessToken,"sr_a_");
        if(deviceId==null) throw invalid();
        var matches=jdbc.query("""
                SELECT s.user_id,s.device_id,s.id FROM auth_access_token t
                JOIN auth_session s ON s.id=t.session_id JOIN app_user u ON u.id=s.user_id
                JOIN device d ON d.id=s.device_id AND d.user_id=s.user_id
                WHERE t.token_hash=? AND t.expires_at>? AND s.expires_at>?
                  AND s.revoked_at IS NULL AND d.revoked_at IS NULL AND u.status='ACTIVE' AND s.device_id=?
                """,(rs,row)->new Principal(uuid(rs.getBytes(1)),uuid(rs.getBytes(2)),uuid(rs.getBytes(3))),
                hash(accessToken),now(),now(),bytes(deviceId));
        if(matches.size()!=1) throw invalid();
        return matches.getFirst();
    }

    private Tokens storeTokens(UUID session,String refresh,LocalDateTime now,LocalDateTime deadline) {
        String access=token("sr_a_");
        LocalDateTime accessExpiry=now.plus(accessTtl);
        if(accessExpiry.isAfter(deadline)) accessExpiry=deadline;
        jdbc.update("INSERT INTO auth_refresh_token(token_hash,session_id,created_at) VALUES(?,?,?)",hash(refresh),bytes(session),now);
        jdbc.update("INSERT INTO auth_access_token(token_hash,session_id,expires_at,created_at) VALUES(?,?,?,?)",hash(access),bytes(session),accessExpiry,now);
        return new Tokens(access,refresh,accessExpiry,deadline);
    }
    private void lockOwner(UUID user,UUID device) {
        if(user==null || device==null) throw invalid();
        var users=jdbc.query("SELECT status FROM app_user WHERE id=? FOR UPDATE",(rs,row)->rs.getString(1),bytes(user));
        if(users.size()!=1 || !"ACTIVE".equals(users.getFirst())) throw invalid();
        var devices=jdbc.query("SELECT revoked_at FROM device WHERE user_id=? AND id=? FOR UPDATE",(rs,row)->rs.getObject(1)==null,bytes(user),bytes(device));
        if(devices.size()!=1 || !devices.getFirst()) throw invalid();
    }
    private static void ownTransaction() {
        if(TransactionSynchronizationManager.isActualTransactionActive())
            throw new IllegalStateException("Session operation must own its transaction");
    }
    private LocalDateTime now() { return LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS); }
    private String token(String prefix) { byte[] value=new byte[32];random.nextBytes(value);return prefix+Base64.getUrlEncoder().withoutPadding().encodeToString(value); }
    private static void checkToken(String token,String prefix) {
        if(token==null || token.length()!=48 || !token.startsWith(prefix) || !token.substring(5).matches("[A-Za-z0-9_-]{43}")) throw invalid();
    }
    private static byte[] hash(String token) {
        try { return MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.US_ASCII)); }
        catch(NoSuchAlgorithmException error) { throw new IllegalStateException("SHA-256 unavailable"); }
    }
    private static byte[] bytes(UUID id) { return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array(); }
    private static UUID uuid(byte[] value) { var b=ByteBuffer.wrap(value);return new UUID(b.getLong(),b.getLong()); }
    private static ApiException invalid() { return new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","다시 로그인해 주세요.",false,Map.of()); }
    public record Principal(UUID userId,UUID deviceId,UUID sessionId) {}
    public record Tokens(String accessToken,String refreshToken,LocalDateTime accessExpiresAt,LocalDateTime refreshExpiresAt) {
        @Override public String toString() { return "Tokens[REDACTED]"; }
    }
    private record SessionRow(byte[] refreshHash,LocalDateTime expiresAt,boolean revoked) {}
    private record Outcome(Tokens tokens,boolean reused) {}
}
