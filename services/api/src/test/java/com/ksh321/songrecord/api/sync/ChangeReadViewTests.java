package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class ChangeReadViewTests {
    final UUID owner=UUID.randomUUID(),other=UUID.randomUUID();
    final Instant now=Instant.parse("2026-10-01T00:00:00Z");
    DriverManagerDataSource source;JdbcTemplate jdbc;AccountAccess access;AccountAccess.Account account;ChangeReadView view;
    @BeforeEach void setup(){
        source=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        initialize();
    }
    void initialize(){
        jdbc=new JdbcTemplate(source);
        jdbc.execute("CREATE TABLE user_sync_state(user_id BINARY(16) PRIMARY KEY,last_change_seq BIGINT NOT NULL,retained_from_seq BIGINT NOT NULL)");
        jdbc.execute("CREATE TABLE change_log(user_id BINARY(16),change_seq BIGINT,entity_type VARCHAR(64),entity_id BINARY(16),revision BIGINT,operation VARCHAR(16),payload VARCHAR(4000),expires_at DATETIME(3),PRIMARY KEY(user_id,change_seq))");
        jdbc.update("INSERT INTO user_sync_state VALUES(?,3,1)",bytes(owner));
        jdbc.update("INSERT INTO user_sync_state VALUES(?,1,1)",bytes(other));
        for(int seq=1;seq<=3;seq++)insert(owner,seq,now.plusSeconds(100));
        insert(other,1,now.plusSeconds(100));
        access=mock(AccountAccess.class);account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        view=new ChangeReadView(source,access,Clock.fixed(now,ZoneOffset.UTC));
    }
    void insert(UUID user,long seq,Instant expiry){jdbc.update("INSERT INTO change_log VALUES(?,?,'SONG',?,1,'UPSERT','{}',?)",bytes(user),seq,bytes(user),LocalDateTime.ofInstant(expiry,ZoneOffset.UTC));}
    @AfterEach void cleanup(){jdbc.execute("SHUTDOWN");}
    @Test void accountScopedLookaheadResumesWithoutRepeatingOrSkipping()throws Exception{
        var first=view.read(account,0,2);assertThat(first.nextSequence()).isEqualTo(2);assertThat(first.hasMore()).isTrue();
        assertThat(first.entries()).allSatisfy(e->assertThat(e.change().id()).isEqualTo(owner));
        var last=view.read(account,first.nextSequence(),2);assertThat(last.entries()).extracting(ChangeWindow.Entry::sequence).containsExactly(3L);
        assertThat(last.hasMore()).isFalse();assertThat(view.read(account,3,2).entries()).isEmpty();
    }
    @Test void staleRetentionAndUncollectedExpiredRowsCannotBeSkipped(){
        jdbc.update("UPDATE user_sync_state SET retained_from_seq=2 WHERE user_id=?",bytes(owner));
        assertThatThrownBy(()->view.read(account,0,2)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CURSOR_EXPIRED"));
        jdbc.update("UPDATE change_log SET expires_at=? WHERE user_id=? AND change_seq=3",LocalDateTime.ofInstant(now,ZoneOffset.UTC),bytes(owner));
        assertThatThrownBy(()->view.read(account,1,1)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CURSOR_EXPIRED"));
    }
    @Test void anotherAccountsExpiredHistoryDoesNotExpireThisAccount()throws Exception{
        jdbc.update("UPDATE change_log SET expires_at=? WHERE user_id=?",LocalDateTime.ofInstant(now,ZoneOffset.UTC),bytes(other));
        assertThat(view.read(account,0,3).nextSequence()).isEqualTo(3);
    }
    @Test void missingRowsAreNotReportedAsCaughtUp(){
        jdbc.update("DELETE FROM change_log WHERE user_id=? AND change_seq=2",bytes(owner));
        assertThatThrownBy(()->view.read(account,0,3)).isInstanceOf(IllegalStateException.class).hasMessage("Noncontiguous change page");
    }
    @Test void finalSessionRevocationPreventsReturningReadData(){
        var principal=new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal).thenThrow(new IllegalStateException("revoked"));
        assertThatThrownBy(()->view.read(account,0,3)).isInstanceOf(IllegalStateException.class).hasMessage("revoked");
    }
    @Test void refusesAnAmbientTransactionAndDeadlineOverrun(){
        assertThatThrownBy(()->new TransactionTemplate(new DataSourceTransactionManager(source)).execute(s->{try{return view.read(account,0,3);}catch(java.sql.SQLException e){throw new RuntimeException(e);}}))
            .isInstanceOf(IllegalStateException.class).hasMessage("Change reads require an independent transaction");
        Clock advancing=mock(Clock.class);when(advancing.instant()).thenReturn(now,now,now.plusSeconds(15));
        var timed=new ChangeReadView(source,access,advancing);
        assertThatThrownBy(()->timed.read(account,0,3)).isInstanceOf(IllegalStateException.class).hasMessage("Change read deadline exceeded");
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
