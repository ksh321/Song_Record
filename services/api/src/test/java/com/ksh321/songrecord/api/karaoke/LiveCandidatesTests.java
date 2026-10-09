package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.songs.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class LiveCandidatesTests {
    final Instant issued=Instant.parse("2026-01-01T00:00:00Z");final byte[] key=new byte[32];final UUID owner=UUID.randomUUID();
    Clock clock(Instant t){return Clock.fixed(t,ZoneOffset.UTC);}
    MananaSearchAdapter.Candidate candidate(CandidateVerifier.Brand brand,String number,String title){return new MananaSearchAdapter.Candidate(brand,number,title,"가수","MANANA","manana:"+(brand==CandidateVerifier.Brand.TJ?"tj":"kumyoung")+":"+number);}
    String token(CandidateVerifier.Brand brand){var source=new SourceTokens(key,clock(issued));return source.encode(source.issueProof(candidate(brand,"00123","원본 (LIVE)")));}
    @Test void freshProofUsesOriginalsWithoutProviderAndExpiredProofRefreshesExactLeadingZeroNumber(){
        var calls=new AtomicInteger();var later=clock(issued.plusSeconds(86400));
        KaraokeSearch.Provider provider=(brand,kind,q)->{calls.incrementAndGet();assertThat(brand).isEqualTo(CandidateVerifier.Brand.TJ);assertThat(kind).isEqualTo(MananaSearchAdapter.Kind.NUMBER);assertThat(q).isEqualTo("00123");return List.of(candidate(brand,q,"수정된 원본"));};
        var fresh=new LiveCandidates(new SourceTokens(key,clock(issued)),provider,new SearchLimit(clock(issued)),clock(issued));
        assertThat(fresh.prepare(token(CandidateVerifier.Brand.TJ),owner).title()).isEqualTo("원본 (LIVE)");assertThat(calls).hasValue(0);
        var service=new TjCandidates(new LiveCandidates(new SourceTokens(key,later),provider,new SearchLimit(later),later),later);
        var c=service.prepare(token(CandidateVerifier.Brand.TJ),TjCandidates.Purpose.SONG,owner);
        assertThat(c.number()).isEqualTo("00123");assertThat(c.title()).isEqualTo("수정된 원본");assertThat(c.issuedAt()).isEqualTo(later.instant());assertThat(calls).hasValue(1);
    }
    @Test void missingOrDifferentNumberCannotBeSubstituted(){
        var later=clock(issued.plusSeconds(86400));
        for(var rows:List.of(List.<MananaSearchAdapter.Candidate>of(),List.of(candidate(CandidateVerifier.Brand.TJ,"123","원본")),List.of(candidate(CandidateVerifier.Brand.KY,"00123","원본")))){
            var service=new LiveCandidates(new SourceTokens(key,later),(b,k,q)->rows,new SearchLimit(later),later);
            assertThatThrownBy(()->service.prepare(token(CandidateVerifier.Brand.TJ),owner)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("SOURCE_CANDIDATE_NOT_FOUND"));
        }
    }
    @Test void outageIsRetryableAndBrandTamperingNeverCallsProvider(){
        var later=clock(issued.plusSeconds(86400));var calls=new AtomicInteger();
        var source=new LiveCandidates(new SourceTokens(key,later),(b,k,q)->{calls.incrementAndGet();throw new MananaSearchAdapter.ProviderFailure(MananaSearchAdapter.Failure.TIMEOUT);},new SearchLimit(later),later);
        assertThatThrownBy(()->source.prepare(token(CandidateVerifier.Brand.TJ),owner)).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).isEqualTo("CANDIDATE_VERIFICATION_UNAVAILABLE");assertThat(e.status().value()).isEqualTo(503);});
        var tj=new TjCandidates(source,later);assertThatThrownBy(()->tj.prepare(token(CandidateVerifier.Brand.KY),TjCandidates.Purpose.PLAYLIST,owner)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->tj.prepare(token(CandidateVerifier.Brand.TJ)+"x",TjCandidates.Purpose.SONG,owner)).isInstanceOf(ApiException.class);
        assertThat(calls).hasValue(1);
    }
}
