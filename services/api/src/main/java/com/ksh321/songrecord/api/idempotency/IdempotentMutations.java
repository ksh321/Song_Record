package com.ksh321.songrecord.api.idempotency;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;

/** Receipt and database-only mutation commit together. Never run external effects in the callback. */
public final class IdempotentMutations {
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate tx;
    private final Clock clock;

    public IdempotentMutations(JdbcTemplate jdbc, AccountAccess access,
            PlatformTransactionManager manager, Clock clock) {
        this.jdbc = jdbc; this.access = access; this.clock = clock;
        tx = new TransactionTemplate(manager);
        tx.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
        tx.setTimeout(30);
    }

    /** Call at the command boundary, before acquiring any domain locks. */
    public Reply execute(AccountAccess.Account account, String key, String method, String target,
            String body, Supplier<Reply> mutation) {
        if (TransactionSynchronizationManager.isActualTransactionActive())
            throw new IllegalStateException("Mutation boundary must own its transaction");
        var owner = access.revalidate(account);
        UUID op = operationId(key);
        String hash = CanonicalRequest.hash(method, target, body);
        Objects.requireNonNull(mutation);
        try {
            return tx.execute(status -> {
                access.revalidate(account);
                var now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);
                try {
                    // The unique key serializes identical account/op requests across server instances.
                    // This provisional row cannot be seen by another transaction before commit.
                    jdbc.update("INSERT INTO mutation_receipt(user_id,op_id,request_hash,response_status,response_body,created_at,expires_at) VALUES(?,?,?,202,NULL,?,?)",
                            bytes(owner.userId()), bytes(op), hash, now, now.plusDays(90));
                } catch (DuplicateKeyException e) { throw new ExistingReceipt(); }
                Reply reply = Objects.requireNonNull(mutation.get());
                jdbc.update("UPDATE mutation_receipt SET response_status=?,response_body=? WHERE user_id=? AND op_id=?",
                        reply.status(), reply.body(), bytes(owner.userId()), bytes(op));
                return reply;
            });
        } catch (ExistingReceipt e) {
            // The failed claim transaction has rolled back. A domain DuplicateKeyException is NOT replay.
            return tx.execute(status -> {
                access.revalidate(account);
                var rows = jdbc.query("SELECT request_hash,response_status,response_body FROM mutation_receipt WHERE user_id=? AND op_id=?",
                        (rs, row) -> new Receipt(rs.getString(1), rs.getInt(2), rs.getString(3)),
                        bytes(owner.userId()), bytes(op));
                if (rows.isEmpty()) throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,
                        "IDEMPOTENCY_RETRY", "잠시 후 다시 시도해 주세요.", true, Map.of());
                var receipt = rows.getFirst();
                if (!hash.equals(receipt.hash())) throw new ApiException(HttpStatus.CONFLICT,
                        "IDEMPOTENCY_CONFLICT", "같은 요청 키를 다른 요청에 사용할 수 없습니다.", false, Map.of());
                return new Reply(receipt.status(), receipt.body());
            });
        }
    }

    /** Successful command responses only; exceptions roll back and remain retryable with the same key. */
    public record Reply(int status, String body) {
        public Reply {
            if (status < 200 || status > 299 || (status == 204 && body != null))
                throw new IllegalArgumentException("Invalid mutation response");
            if (body != null) body = CanonicalRequest.canonical(body);
        }
        @Override public String toString() { return "Reply[status=" + status + ", body=REDACTED]"; }
    }
    private record Receipt(String hash, int status, String body) {}
    private static final class ExistingReceipt extends RuntimeException {}
    private static UUID operationId(String key) {
        try {
            var id = UUID.fromString(key);
            if (!id.toString().equals(key)) throw CanonicalRequest.invalid();
            return id;
        } catch (IllegalArgumentException | NullPointerException e) { throw CanonicalRequest.invalid(); }
    }
    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
}
