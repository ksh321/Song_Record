package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.pagination.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.pagination.PageTestSource.bytes;

class PaginationTests {
    final IdempotencyTests f = new IdempotencyTests();
    PageCursor codec; KeysetPages pages; PageTestSource source; UUID owner;
    PageCursor.Query query(int limit) { return new PageCursor.Query("test/items", "RANK_DESC", "1", "{}", limit); }
    @BeforeEach void setup() throws Exception {
        f.setup(); owner = f.registration.userId();
        f.jdbc.execute("CREATE TABLE page_item(id BINARY(16) PRIMARY KEY,user_id BINARY(16),rank_no INT)");
        byte[] key = new byte[32]; new java.security.SecureRandom().nextBytes(key);
        codec = new PageCursor(key, f.clock, Duration.ofMinutes(5));
        pages = new KeysetPages(f.jdbc, f.access, f.manager, codec); source = new PageTestSource();
    }
    @AfterEach void close() throws Exception { f.close(); }
    UUID insert(int i, int rank) { var id = new UUID(i % 2 == 0 ? Long.MIN_VALUE : 0, i); f.jdbc.update("INSERT INTO page_item VALUES(?,?,?)", bytes(id), bytes(owner), rank); return id; }
    void error(Runnable work, String code) {
        assertThatThrownBy(work::run).isInstanceOfSatisfying(ApiException.class, e -> {
            assertThat(e.code()).isEqualTo(code); assertThat(e.details()).isEmpty();
        });
    }
    @Test void defaultAndLimitBoundaries() {
        assertThat(PageCursor.pageSize(null)).isEqualTo(50); assertThat(PageCursor.pageSize(1)).isEqualTo(1); assertThat(PageCursor.pageSize(100)).isEqualTo(100);
        for(int size : new int[]{-1, 0, 101, Integer.MAX_VALUE}) error(() -> PageCursor.pageSize(size), "VALIDATION_ERROR");
    }
    @Test void tiesAcrossPagesUseUnsignedUuidWithoutDuplicatesOrGaps() {
        for(int i=1;i<=125;i++) insert(i, i % 3);
        var expected = source.fetch(f.jdbc, owner, null, 200).stream().map(KeysetPages.Entry::item).toList();
        var actual = new ArrayList<UUID>(); String cursor = null; int rounds = 0;
        do {
            var page = pages.query(f.account, query(50), cursor, source);
            assertThat(page.count()).isEqualTo(125); actual.addAll(page.items()); cursor = page.next_cursor(); rounds++;
        } while(cursor != null && rounds < 10);
        assertThat(rounds).isEqualTo(3); assertThat(actual).containsExactlyElementsOf(expected).doesNotHaveDuplicates();
    }
    @Test void emptyExactBoundaryAndLimitOne() {
        assertThat(pages.query(f.account, query(1), null, source)).isEqualTo(new KeysetPages.Page<>(List.of(), 0, null));
        var a=insert(1,1);insert(2,1);
        var first=pages.query(f.account,query(1),null,source);assertThat(first.items()).containsExactly(a);
        assertThat(pages.query(f.account,query(1),first.next_cursor(),source).next_cursor()).isNull();
        assertThat(pages.query(f.account,query(2),null,source).next_cursor()).isNull();
    }
    @Test void changedQueryOwnerRouteSortVersionOrLimitRejectsCursor() {
        insert(1,1);insert(2,1);String cursor=pages.query(f.account,query(1),null,source).next_cursor();
        error(() -> pages.query(f.other,query(1),cursor,source),"INVALID_CURSOR");
        for(var q:List.of(new PageCursor.Query("other","RANK_DESC","1","{}",1),
                new PageCursor.Query("test/items","TITLE","1","{}",1),new PageCursor.Query("test/items","RANK_DESC","2","{}",1),
                new PageCursor.Query("test/items","RANK_DESC","1","{\"search\":\"x\"}",1),query(2)))
            error(() -> pages.query(f.account,q,cursor,source),"INVALID_CURSOR");
    }
    @Test void generationChangeRequiresRestartAndUpdatedCount() {
        insert(1,1);insert(2,1);String cursor=pages.query(f.account,query(1),null,source).next_cursor();
        new TransactionTemplate(f.manager).executeWithoutResult(s->{insert(3,3);f.jdbc.update("UPDATE user_sync_state SET last_change_seq=1 WHERE user_id=?",bytes(owner));});
        error(() -> pages.query(f.account,query(1),cursor,source),"LIST_CURSOR_EXPIRED");
        assertThat(pages.query(f.account,query(1),null,source).count()).isEqualTo(3);
    }
    @Test void expiryAtBoundaryAndMalformedOrTamperedTokens() {
        var tuple=new PageCursor.Tuple(Arrays.asList("private-search",null),UUID.randomUUID());
        String token=codec.issue(owner,query(1),0,tuple);
        assertThat(codec.read(token,owner,query(1)).after()).isEqualTo(tuple);
        assertThat(token).doesNotContain("private-search");
        byte[] wire=Base64.getUrlDecoder().decode(token.substring(3));wire[wire.length-1]^=1;
        for(String bad:List.of("", " ", "p2.x",token+"=","p1."+Base64.getUrlEncoder().withoutPadding().encodeToString(wire),"x".repeat(8193)))
            error(() -> codec.read(bad,owner,query(1)),"INVALID_CURSOR");
        f.clock.instant=f.clock.instant.plusSeconds(300);error(() -> codec.read(token,owner,query(1)),"LIST_CURSOR_EXPIRED");
    }
    @Test void queryCanonicalizationAndFreshIv() {
        var a=new PageCursor.Query("items","TITLE","1","{\"b\":2,\"a\":1}",50);
        var b=new PageCursor.Query("items","TITLE","1","{\"a\":1.0,\"b\":2}",50);
        var tuple=new PageCursor.Tuple(List.of("title"),UUID.randomUUID());String one=codec.issue(owner,a,1,tuple);
        assertThat(codec.read(one,owner,b).after()).isEqualTo(tuple);assertThat(codec.issue(owner,a,1,tuple)).isNotEqualTo(one);
    }
    @Test void differentServerKeyRejectsAndSameKeySurvivesInstanceRestart() {
        byte[] key=new byte[32];Arrays.fill(key,(byte)17);var a=new PageCursor(key,f.clock,Duration.ofMinutes(5));
        String token=a.issue(owner,query(1),0,new PageCursor.Tuple(List.of("1"),UUID.randomUUID()));
        assertThat(new PageCursor(key,f.clock,Duration.ofMinutes(5)).read(token,owner,query(1)).generation()).isZero();
        error(()->codec.read(token,owner,query(1)),"INVALID_CURSOR");
    }
    @Test void pageSourceMustBeStrictlyAfterCursorAndOrdered() {
        insert(1,1);insert(2,1);
        var bad=new PageTestSource(){@Override public List<KeysetPages.Entry<UUID>> fetch(org.springframework.jdbc.core.JdbcTemplate jdbc,UUID id,PageCursor.Tuple after,int max){var rows=new ArrayList<>(super.fetch(jdbc,id,null,max));Collections.reverse(rows);return rows;}};
        assertThatThrownBy(()->pages.query(f.account,query(2),null,bad)).isInstanceOf(IllegalStateException.class);
    }
    @Test void outerTransactionIsRejectedAndOtherAccountReadsNothing() {
        insert(1,1);assertThat(pages.query(f.other,query(50),null,source).items()).isEmpty();
        assertThatThrownBy(()->new TransactionTemplate(f.manager).execute(s->pages.query(f.account,query(50),null,source))).isInstanceOf(IllegalStateException.class);
    }
}
