package com.ksh321.songrecord.api.auth;

import java.nio.ByteBuffer;
import java.util.Optional;
import java.util.UUID;
import org.springframework.dao.IncorrectResultSizeDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;

public final class JdbcAuthIdentityRepository implements AuthIdentityRepository {
    private final JdbcTemplate jdbc;

    public JdbcAuthIdentityRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @Override
    public Optional<AuthIdentity> find(VerifiedProviderIdentity identity) {
        var rows = jdbc.query("""
                SELECT id, user_id, provider, provider_user_id
                FROM auth_identity WHERE provider = ? AND provider_user_id = ?
                """, (rs, row) -> new AuthIdentity(uuid(rs.getBytes("id")), uuid(rs.getBytes("user_id")),
                        rs.getString("provider"), rs.getString("provider_user_id")),
                identity.provider(), identity.providerUserId());
        if (rows.size() > 1) throw new IncorrectResultSizeDataAccessException(1, rows.size());
        return rows.stream().findFirst();
    }

    private static UUID uuid(byte[] bytes) {
        if (bytes == null || bytes.length != 16) throw new IllegalStateException("Invalid persisted UUID");
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        return new UUID(buffer.getLong(), buffer.getLong());
    }
}
