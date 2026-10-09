package com.ksh321.songrecord.api.karaoke;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;

/** Sliding minute, shared by all devices/search kinds of an authenticated account. */
public final class SearchLimit {
    private final Clock clock;
    private final Map<UUID,ArrayDeque<Instant>> calls=new HashMap<>();
    public SearchLimit(Clock clock){this.clock=clock;}
    public synchronized void acquire(UUID owner){
        Objects.requireNonNull(owner);
        var now=clock.instant();var cutoff=now.minusSeconds(60);
        calls.values().forEach(q->{while(!q.isEmpty() && !q.peekFirst().isAfter(cutoff))q.removeFirst();});
        calls.values().removeIf(ArrayDeque::isEmpty);
        var q=calls.get(owner);
        if(q==null){if(calls.size()>=10000)throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"SEARCH_CAPACITY_UNAVAILABLE","검색이 잠시 혼잡합니다.",true,Map.of());q=new ArrayDeque<>();calls.put(owner,q);}
        if(q.size()>=30)throw new ApiException(HttpStatus.TOO_MANY_REQUESTS,"SEARCH_RATE_LIMITED","잠시 후 다시 검색해 주세요.",true,Map.of("retry_after_seconds",Math.max(1,60-Duration.between(q.peekFirst(),now).toSeconds())));
        q.addLast(now);
    }
}
