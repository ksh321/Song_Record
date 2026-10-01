package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.Instant;
import java.util.*;
import org.springframework.http.HttpStatus;

/** P10-06: validates one account's consistent change-log read before issuing a cursor.
 * The authenticated repository must supply head, retention floor and limit+1 rows
 * from the same read view. This class grants no account access by itself.
 */
public final class ChangeWindow {
    private ChangeWindow() {}
    public record Entry(long sequence, AccountChanges.Change change, Instant expiresAt) {
        public Entry {
            if(sequence<1)throw new IllegalArgumentException("Positive sequence required");
            Objects.requireNonNull(change);Objects.requireNonNull(expiresAt);
        }
        @Override public String toString(){return "ChangeWindowEntry[REDACTED]";}
    }
    public record Page(long afterSequence,long nextSequence,long head,boolean hasMore,List<Entry> entries) {
        public Page {entries=List.copyOf(entries);}
        @Override public String toString(){return "ChangeWindowPage[REDACTED]";}
    }
    public static Page validate(long after,long head,long retainedFrom,int limit,List<Entry> rows,Instant now) {
        Objects.requireNonNull(rows);Objects.requireNonNull(now);
        checkPosition(after,head,retainedFrom,limit);
        if(rows.size()>limit+1)throw new IllegalStateException("Unbounded change page");
        long previous=after;
        for(var row:rows) {
            if(previous==Long.MAX_VALUE||row.sequence()!=previous+1||row.sequence()>head)
                throw new IllegalStateException("Noncontiguous change page");
            if(!row.expiresAt().isAfter(now))throw expired();
            previous=row.sequence();
        }
        // A missing row is never permission to jump to head or report caught up.
        if(rows.size()<=limit&&previous!=head)throw new IllegalStateException("Incomplete change page");
        var returned=List.copyOf(rows.subList(0,Math.min(limit,rows.size())));
        long next=returned.isEmpty()?after:returned.getLast().sequence();
        return new Page(after,next,head,rows.size()>limit,returned);
    }
    static void checkPosition(long after,long head,long retainedFrom,int limit) {
        if(after<0||limit<1||limit>100)throw invalid();
        if(head<0||retainedFrom<1||retainedFrom-1>head)throw new IllegalStateException("Invalid change-log bounds");
        if(after>head)throw invalid();
        if(after<retainedFrom-1)throw expired();
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"INVALID_CURSOR","동기화 위치를 확인해 주세요.",false,Map.of());}
    static ApiException expired(){return new ApiException(HttpStatus.CONFLICT,"CURSOR_EXPIRED","초기 정보를 다시 받아야 해요.",false,Map.of());}
}
