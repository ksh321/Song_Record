package com.ksh321.songrecord.api.sync;

import java.time.Instant;
import java.util.*;
import com.ksh321.songrecord.api.web.ApiException;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class ChangeWindowTests {
    final Instant now=Instant.parse("2026-10-01T00:00:00Z");
    ChangeWindow.Entry entry(long seq){return new ChangeWindow.Entry(seq,
        new AccountChanges.Change(AccountChanges.Entity.SONG,UUID.randomUUID(),1,AccountChanges.Operation.UPSERT,"{\"note\":\"synthetic-private\"}"),now.plusSeconds(1));}
    @Test void advancesOnlyToReturnedRowsAndRetainsLookahead(){
        var p=ChangeWindow.validate(3,6,1,2,List.of(entry(4),entry(5),entry(6)),now);
        assertThat(p.nextSequence()).isEqualTo(5);assertThat(p.head()).isEqualTo(6);assertThat(p.hasMore()).isTrue();
        assertThat(p.entries()).extracting(ChangeWindow.Entry::sequence).containsExactly(4L,5L);
        assertThatThrownBy(()->p.entries().clear()).isInstanceOf(UnsupportedOperationException.class);
        assertThat(p.toString()).doesNotContain("synthetic-private");assertThat(p.entries().getFirst().toString()).doesNotContain("synthetic-private");
    }
    @Test void caughtUpAndEmptyAccountsDoNotInventAdvance(){
        assertThat(ChangeWindow.validate(0,0,1,50,List.of(),now).nextSequence()).isZero();
        var p=ChangeWindow.validate(Long.MAX_VALUE,Long.MAX_VALUE,Long.MAX_VALUE,1,List.of(),now);
        assertThat(p.nextSequence()).isEqualTo(Long.MAX_VALUE);assertThat(p.hasMore()).isFalse();
    }
    @Test void retentionBoundaryAllowsExactlyPreviousSequence(){
        assertThat(ChangeWindow.validate(5,5,6,50,List.of(),now).nextSequence()).isEqualTo(5);
        assertThat(ChangeWindow.validate(4,5,5,50,List.of(entry(5)),now).nextSequence()).isEqualTo(5);
        assertThatThrownBy(()->ChangeWindow.validate(3,5,5,50,List.of(entry(4),entry(5)),now))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CURSOR_EXPIRED"));
    }
    @Test void deletionRevisionAndPayloadArePreservedWithoutReinterpretingThem(){
        var change=new AccountChanges.Change(AccountChanges.Entity.RECORDING,UUID.randomUUID(),9,
                AccountChanges.Operation.DELETE,"{\"deleted\":true}");
        var row=new ChangeWindow.Entry(1,change,now.plusSeconds(10));
        var page=ChangeWindow.validate(0,1,1,50,List.of(row),now);
        assertThat(page.entries().getFirst().change()).isSameAs(change);
        assertThat(page.entries().getFirst().change().revision()).isEqualTo(9);
        assertThat(page.entries().getFirst().change().operation()).isEqualTo(AccountChanges.Operation.DELETE);
    }
    @Test void expiryAtExactBoundaryIsRejectedEvenBeforeCleanup(){
        var live=entry(1);var expired=new ChangeWindow.Entry(1,live.change(),now);
        assertThatThrownBy(()->ChangeWindow.validate(0,1,1,50,List.of(expired),now))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CURSOR_EXPIRED"));
    }
    @Test void gapDuplicateDescendingAndTruncatedTailNeverIssueCursor(){
        for(var rows:List.of(List.of(entry(2)),List.of(entry(1),entry(1)),List.of(entry(2),entry(1)),List.<ChangeWindow.Entry>of()))
            assertThatThrownBy(()->ChangeWindow.validate(0,2,1,50,rows,now)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(()->ChangeWindow.validate(0,3,1,50,List.of(entry(1),entry(2)),now)).isInstanceOf(IllegalStateException.class);
    }
    @Test void malformedRequestedAndSourceBoundsAreDistinct(){
        for(int limit:new int[]{0,101})assertThatThrownBy(()->ChangeWindow.validate(0,0,1,limit,List.of(),now)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->ChangeWindow.validate(2,1,1,1,List.of(),now)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->ChangeWindow.validate(-1,1,1,1,List.of(),now)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->ChangeWindow.validate(0,0,2,1,List.of(),now)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(()->ChangeWindow.validate(0,3,1,1,List.of(entry(1),entry(2),entry(3)),now)).isInstanceOf(IllegalStateException.class);
    }
    @Test void sequenceNearLongMaximumDoesNotOverflow(){
        var p=ChangeWindow.validate(Long.MAX_VALUE-1,Long.MAX_VALUE,1,1,List.of(entry(Long.MAX_VALUE)),now);
        assertThat(p.nextSequence()).isEqualTo(Long.MAX_VALUE);assertThat(p.hasMore()).isFalse();
        assertThatThrownBy(()->ChangeWindow.validate(Long.MAX_VALUE,Long.MAX_VALUE,1,1,List.of(entry(1)),now)).isInstanceOf(IllegalStateException.class);
    }
}
