package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
class SearchPolicyTests {
    static class MovingClock extends Clock {Instant now=Instant.parse("2026-01-01T00:00:00Z");public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId z){return this;}public Instant instant(){return now;}}
    @Test void slidingWindowSharesAccountAcrossQueriesAndReopensAtExactlyOneMinute(){
        var clock=new MovingClock();var limit=new SearchLimit(clock);var owner=UUID.randomUUID();
        for(int i=0;i<30;i++)limit.acquire(owner);
        assertThatThrownBy(()->limit.acquire(owner)).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).isEqualTo("SEARCH_RATE_LIMITED");assertThat(e.status().value()).isEqualTo(429);});
        limit.acquire(UUID.randomUUID());clock.now=clock.now.plusSeconds(59);assertThatThrownBy(()->limit.acquire(owner)).isInstanceOf(ApiException.class);clock.now=clock.now.plusSeconds(1);limit.acquire(owner);
    }
    @Test void concurrentAccountRequestsNeverExceedThirty()throws Exception{
        var limit=new SearchLimit(Clock.systemUTC());var owner=UUID.randomUUID();
        try(var pool=Executors.newFixedThreadPool(8)){var tasks=new ArrayList<Callable<Boolean>>();for(int i=0;i<60;i++)tasks.add(()->{try{limit.acquire(owner);return true;}catch(ApiException e){return false;}});int count=0;for(var f:pool.invokeAll(tasks))if(f.get())count++;assertThat(count).isEqualTo(30);}
    }
    @Test void emptySuccessAndFourFailuresAreDistinctAndSessionRevalidated(){
        var access=mock(AccountAccess.class);var account=mock(AccountAccess.Account.class);var principal=new SessionService.Principal(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID());when(access.revalidate(account)).thenReturn(principal);
        var limit=new SearchLimit(Clock.systemUTC());var search=new KaraokeSearch(access,limit,(b,k,q)->List.of());assertThat(search.search(account,Brand.TJ,MananaSearchAdapter.Kind.TITLE," 곡 ")).isEmpty();verify(access,times(2)).revalidate(account);
        for(var f:MananaSearchAdapter.Failure.values()){var failing=new KaraokeSearch(access,limit,(b,k,q)->{throw new MananaSearchAdapter.ProviderFailure(f);});assertThatThrownBy(()->failing.search(account,Brand.TJ,MananaSearchAdapter.Kind.TITLE,"곡")).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).startsWith("SEARCH_");assertThat(e.retryable()).isTrue();assertThat(e.details()).isEmpty();});}
        verify(access,times(6)).revalidate(account);
        assertThatThrownBy(()->search.search(account,Brand.TJ,MananaSearchAdapter.Kind.NUMBER,"1/2")).isInstanceOf(ApiException.class);
    }
}
