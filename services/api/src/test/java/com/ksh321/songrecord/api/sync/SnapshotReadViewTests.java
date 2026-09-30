package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import java.nio.ByteBuffer;
import java.sql.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class SnapshotReadViewTests {
    final UUID owner=UUID.randomUUID();
    final Instant now=Instant.parse("2026-09-30T00:00:00Z");
    DriverManagerDataSource source;
    JdbcTemplate jdbc;
    AccountAccess access;
    AccountAccess.Account account;
    SnapshotReadView view;
    @BeforeEach void setup() {
        source=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        jdbc=new JdbcTemplate(source);
        jdbc.execute("CREATE TABLE user_sync_state(user_id BINARY(16) PRIMARY KEY,last_change_seq BIGINT)");
        jdbc.execute("CREATE TABLE song(user_id BINARY(16),note VARCHAR(100))");
        jdbc.update("INSERT INTO user_sync_state VALUES(?,7)",bytes(owner));
        jdbc.update("INSERT INTO song VALUES(?,'before')",bytes(owner));
        access=mock(AccountAccess.class);account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        view=new SnapshotReadView(source,access,Clock.fixed(now,ZoneOffset.UTC));
    }
    @AfterEach void cleanup(){jdbc.execute("SHUTDOWN");}
    String note(Connection connection,UUID id)throws SQLException {
        try(var query=connection.prepareStatement("SELECT note FROM song WHERE user_id=?")) {
            query.setBytes(1,bytes(id));try(var result=query.executeQuery()){result.next();return result.getString(1);}
        }
    }
    @Test void failureClosesTheReadConnectionAndNextCaptureStartsFresh() throws Exception {
        Connection[] observed=new Connection[1];
        assertThatThrownBy(()->view.capture(account,now,(c,id)->{
            observed[0]=c;throw new SQLException("synthetic failure");
        })).isInstanceOf(SQLException.class);
        assertThat(observed[0].isClosed()).isTrue();
        assertThat(view.capture(account,now,this::note).value()).isEqualTo("before");
    }
    @Test void missingOwnerAndExpiredBuildCannotPublishCapture() {
        assertThatThrownBy(()->view.capture(account,now.minusSeconds(600),this::note)).isInstanceOf(IllegalStateException.class);
        jdbc.update("DELETE FROM user_sync_state");
        assertThatThrownBy(()->view.capture(account,now,this::note)).isInstanceOf(IllegalStateException.class);
    }
    @Test void revocationAfterReadingPreventsReturningData() {
        var principal=new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal).thenThrow(new IllegalStateException("revoked"));
        assertThatThrownBy(()->view.capture(account,now,this::note)).isInstanceOf(IllegalStateException.class).hasMessage("revoked");
    }
    @Test void deadlineReachedDuringExtractionCannotPublishCapture() {
        Clock advancing=mock(Clock.class);
        when(advancing.instant()).thenReturn(now,now,now.plusSeconds(600));
        var timed=new SnapshotReadView(source,access,advancing);
        assertThatThrownBy(()->timed.capture(account,now,this::note))
                .isInstanceOf(IllegalStateException.class).hasMessage("Snapshot build deadline exceeded");
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
