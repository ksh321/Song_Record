package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;
class SourceTokenTests {
    final Instant now=Instant.parse("2026-01-01T00:00:00Z");
    final byte[] key=new byte[32];
    MananaSearchAdapter.Candidate candidate(Brand brand){return new MananaSearchAdapter.Candidate(brand,"00123","원본 (LIVE)","가수","MANANA","manana:"+(brand==Brand.TJ?"tj":"kumyoung")+":00123");}
    @Test void bindsExactBrandNumberOriginalsAndFixedDayWithTamperRejection(){
        var tokens=new SourceTokens(key,Clock.fixed(now,ZoneOffset.UTC));
        for(var brand:Brand.values()){var proof=tokens.issueProof(candidate(brand));var encoded=tokens.encode(proof);var read=tokens.read(encoded);assertThat(read.candidate()).isEqualTo(candidate(brand));assertThat(read.expiresAt()).isEqualTo(now.plusSeconds(86400));assertThat(encoded).doesNotContain("原本","00123","LIVE");assertThatThrownBy(()->tokens.read(encoded.substring(0,10)+(encoded.charAt(10)=='A'?'B':'A')+encoded.substring(11))).isInstanceOf(ApiException.class);}
        assertThatThrownBy(()->tokens.read("dev-source-tj-001")).isInstanceOf(ApiException.class);
    }
    @Test void proofCarriesExpiryWithoutExtendingItAndUnavailableKeysFailClosed(){
        var tokens=new SourceTokens(key,Clock.fixed(now,ZoneOffset.UTC));var encoded=tokens.encode(tokens.issueProof(candidate(Brand.TJ)));
        var later=new SourceTokens(key,Clock.fixed(now.plusSeconds(86400),ZoneOffset.UTC));assertThat(later.read(encoded).expiresAt()).isEqualTo(now.plusSeconds(86400));
        assertThatThrownBy(()->new SourceTokens(key,Clock.fixed(now.minusSeconds(1),ZoneOffset.UTC)).read(encoded)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->new SourceTokens(null,Clock.systemUTC()).read(encoded)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("SEARCH_SIGNING_UNAVAILABLE"));
        assertThatThrownBy(()->new SourceTokens(new byte[16],Clock.systemUTC())).isInstanceOf(IllegalArgumentException.class);
    }
    @Test void responseExpirationMatchesEncryptedProofAtMillisecondPrecision(){var tokens=new SourceTokens(key,Clock.fixed(now.plusNanos(123456789),ZoneOffset.UTC));var proof=tokens.issueProof(candidate(Brand.TJ));assertThat(tokens.read(tokens.encode(proof)).expiresAt()).isEqualTo(proof.expiresAt());}

}
