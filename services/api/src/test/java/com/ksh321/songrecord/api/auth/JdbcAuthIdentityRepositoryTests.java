package com.ksh321.songrecord.api.auth;

import java.nio.ByteBuffer;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.dao.IncorrectResultSizeDataAccessException;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class JdbcAuthIdentityRepositoryTests {
    private final DataSource source = mock(DataSource.class);
    private final Connection connection = mock(Connection.class);
    private final PreparedStatement statement = mock(PreparedStatement.class);
    private final ResultSet rows = mock(ResultSet.class);
    private JdbcAuthIdentityRepository repository;
    private final UUID id = UUID.fromString("12345678-1234-5678-9012-123456789012");
    @BeforeEach void setup() throws Exception {
        when(source.getConnection()).thenReturn(connection);
        when(connection.prepareStatement(anyString())).thenReturn(statement);
        when(statement.executeQuery()).thenReturn(rows);
        when(rows.getBytes("id")).thenReturn(bytes(id));
        when(rows.getBytes("user_id")).thenReturn(bytes(id));
        when(rows.getString("provider")).thenReturn("KAKAO");
        when(rows.getString("provider_user_id")).thenReturn("123");
        repository = new JdbcAuthIdentityRepository(new JdbcTemplate(source));
    }
    @Test void bindsBothIdentityFieldsAndMapsBinaryUuid() throws Exception {
        when(rows.next()).thenReturn(true, false);
        assertThat(repository.find(new VerifiedProviderIdentity("KAKAO", "123")))
                .contains(new AuthIdentity(id, id, "KAKAO", "123"));
        verify(connection).prepareStatement(contains("WHERE provider = ? AND provider_user_id = ?"));
        verify(statement).setString(1, "KAKAO");
        verify(statement).setString(2, "123");
    }
    @Test void missingIdentityIsEmpty() throws Exception {
        when(rows.next()).thenReturn(false);
        assertThat(repository.find(new VerifiedProviderIdentity("KAKAO", "123"))).isEmpty();
    }
    @Test void duplicateIdentityFailsClosed() throws Exception {
        when(rows.next()).thenReturn(true, true, false);
        assertThatThrownBy(() -> repository.find(new VerifiedProviderIdentity("KAKAO", "123")))
                .isInstanceOf(IncorrectResultSizeDataAccessException.class);
    }
    @Test void malformedPersistedUuidFailsClosed() throws Exception {
        when(rows.next()).thenReturn(true, false);
        when(rows.getBytes("id")).thenReturn(new byte[8]);
        assertThatThrownBy(() -> repository.find(new VerifiedProviderIdentity("KAKAO", "123")))
                .isInstanceOf(IllegalStateException.class);
    }
    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }
}
