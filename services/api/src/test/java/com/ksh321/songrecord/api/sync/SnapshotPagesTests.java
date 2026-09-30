package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class SnapshotPagesTests {
    final UUID owner=UUID.randomUUID(), token=UUID.randomUUID();
    final Instant now=Instant.parse("2026-09-30T00:00:00Z"), expiry=now.plusSeconds(1800);
    JdbcTemplate jdbc;
    AccountAccess access;
    AccountAccess.Account account;
    SnapshotPages pages;
    SnapshotPageCursor cursors;
    final Clock clock=Clock.fixed(now,ZoneOffset.UTC);

    @BeforeEach void setup() {
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        jdbc.execute("CREATE TABLE snapshot_header(id BINARY(16) PRIMARY KEY,user_id BINARY(16),purpose VARCHAR(8),status VARCHAR(16),snapshot_cursor BIGINT,expires_at TIMESTAMP(3))");
        jdbc.execute("CREATE TABLE snapshot_entry(snapshot_id BINARY(16),entity VARCHAR(32),ordinal BIGINT,resource_id BINARY(16),payload VARCHAR(1000),PRIMARY KEY(snapshot_id,entity,ordinal))");
        jdbc.update("INSERT INTO snapshot_header VALUES(?,?,'SYNC','READY',7,?)",bytes(token),bytes(owner),LocalDateTime.ofInstant(expiry,ZoneOffset.UTC));
        access=mock(AccountAccess.class); account=mock(AccountAccess.Account.class);
        when(access.revalidate(account)).thenReturn(new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID()));
        cursors=new SnapshotPageCursor(new byte[32],clock);
        pages=new SnapshotPages(jdbc,access,cursors,clock);
    }
    @AfterEach void cleanup() { jdbc.execute("SHUTDOWN"); }
    void insert(String entity,long ordinal) {
        jdbc.update("INSERT INTO snapshot_entry VALUES(?,?,?,?,?)",bytes(token),entity,ordinal,bytes(UUID.randomUUID()),"{\"revision\":"+ordinal+"}");
    }
    void code(String expected,Runnable action) {
        assertThatThrownBy(action::run).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo(expected));
    }
    SnapshotPages.Page read(String cursor,Integer limit) {return pages.read(account,token,SnapshotPages.Entity.SONG,cursor,limit);}

    @Test void pagesUseStoredRowsAndResumeWithSameCursorAndFixedBaseline() {
        insert("SONG",1);insert("SONG",2);insert("SONG",3);insert("TAG",1);
        var first=read(null,2);
        assertThat(first.entries()).extracting(SnapshotPages.Entry::ordinal).containsExactly(1L,2L);
        assertThat(first.snapshotCursor()).isEqualTo(7);
        assertThat(first.nextCursor()).isNotNull();
        // Independent live domain data is not consulted by the page reader.
        jdbc.execute("CREATE TABLE song(note VARCHAR(100))");
        jdbc.update("INSERT INTO song VALUES('edited after snapshot')");
        var second=read(first.nextCursor(),2);
        assertThat(second.entries()).extracting(SnapshotPages.Entry::ordinal).containsExactly(3L);
        assertThat(second.entries().getFirst().payload()).isEqualTo("{\"revision\":3}");
        assertThat(second.snapshotCursor()).isEqualTo(7);
        assertThat(second.expiresAt()).isEqualTo(expiry);
        assertThat(second.nextCursor()).isNull();
        assertThat(read(first.nextCursor(),2)).isEqualTo(second);
        assertThat(first.toString()).isEqualTo("SnapshotPage[REDACTED]");
    }
    @Test void rejectsForeignOwnerExportAndUnpublishedOrExpiredHeaders() {
        jdbc.update("UPDATE snapshot_header SET user_id=?",bytes(UUID.randomUUID()));
        code("SNAPSHOT_NOT_FOUND",()->read(null,50));
        jdbc.update("UPDATE snapshot_header SET user_id=?,purpose='EXPORT'",bytes(owner));
        code("SNAPSHOT_NOT_FOUND",()->read(null,50));
        for(String state:List.of("BUILDING","FAILED")) {
            jdbc.update("UPDATE snapshot_header SET purpose='SYNC',status=?",state);
            code("SNAPSHOT_NOT_READY",()->read(null,50));
        }
        jdbc.update("UPDATE snapshot_header SET status='READY',expires_at=?",LocalDateTime.ofInstant(now,ZoneOffset.UTC));
        code("SNAPSHOT_EXPIRED",()->read(null,50));
    }
    @Test void sessionRevocationDuringReadDoesNotReleaseData() {
        insert("SONG",1);
        var principal=new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal).thenThrow(new ApiException(
                org.springframework.http.HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","expired",false,Map.of()));
        code("AUTH_INVALID_SESSION",()->read(null,50));
    }
    @Test void headerExpiryDuringReadIsCheckedAgain() {
        insert("SONG",1);
        var principal=new SessionService.Principal(owner,UUID.randomUUID(),UUID.randomUUID());
        when(access.revalidate(account)).thenReturn(principal).thenAnswer(invocation->{
            jdbc.update("UPDATE snapshot_header SET status='EXPIRED'");return principal;
        });
        code("SNAPSHOT_EXPIRED",()->read(null,50));
    }
    @Test void limitsEmptyEntityAndCursorScopesAreEnforced() {
        assertThat(read(null,null).entries()).isEmpty();
        for(int limit:new int[]{0,101})code("VALIDATION_ERROR",()->read(null,limit));
        String other=cursors.issue(owner,token,"TAG",1,expiry);
        code("INVALID_CURSOR",()->read(other,50));
        code("INVALID_CURSOR",()->read("",50));
        for(int i=1;i<=101;i++)insert("SONG",i);
        assertThat(read(null,null).entries()).hasSize(50);
        assertThat(read(null,100).entries()).hasSize(100);
        assertThat(read(null,100).nextCursor()).isNotNull();
    }
    static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
}
