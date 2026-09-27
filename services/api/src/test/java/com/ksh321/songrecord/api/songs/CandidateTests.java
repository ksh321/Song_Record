package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import static org.assertj.core.api.Assertions.*;

class CandidateTests {
    final Instant now=Instant.parse("2026-01-01T00:00:00Z");
    final Clock clock=Clock.fixed(now,ZoneOffset.UTC);
    TjCandidates service(Clock reading){return new TjCandidates(new DevelopmentCandidates(clock),reading);}
    void error(Runnable action,String code,int status){assertThatThrownBy(action::run).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.code()).isEqualTo(code);assertThat(e.status().value()).isEqualTo(status);assertThat(e.details()).isEmpty();});}
    @Test void exactProofSuppliesServerOriginals(){
        var candidate=service(clock).require("dev-source-tj-001",TjCandidates.Purpose.SONG);
        assertThat(candidate.brand()).isEqualTo(CandidateVerifier.Brand.TJ);assertThat(candidate.number()).isEqualTo("990001");
        assertThat(candidate.title()).isEqualTo("개발 검증 곡");assertThat(candidate.provider()).isEqualTo("DEVELOPMENT_FIXTURE");
    }
    @Test void sameTitleDifferentNumbersRemainDistinct(){
        var a=service(clock).require("dev-source-tj-001",TjCandidates.Purpose.SONG);var b=service(clock).require("dev-source-tj-002",TjCandidates.Purpose.SONG);
        assertThat(a.title()).isEqualTo(b.title());assertThat(a.number()).isNotEqualTo(b.number());
    }
    @Test void arbitraryBrandNumberJsonAndTamperedProofAreRejected(){
        for(String proof:new String[]{null,"","990001","TJ:990001","{\"brand\":\"TJ\",\"number\":\"990001\"}","dev-source-tj-003","dev-source-tj-001 ","x".repeat(8193)})
            error(()->service(clock).require(proof,TjCandidates.Purpose.SONG),"SOURCE_TOKEN_INVALID",400);
    }
    @Test void verifiedKyStillCannotCreateSongOrPlaylist(){
        error(()->service(clock).require("dev-source-ky-001",TjCandidates.Purpose.SONG),"SONG_TJ_REQUIRED",400);
        error(()->service(clock).require("dev-source-ky-001",TjCandidates.Purpose.PLAYLIST),"PLAYLIST_TJ_REQUIRED",400);
    }
    @Test void expiryIsFixedAtIssuanceAndBoundaryIsExclusive(){
        assertThat(service(Clock.fixed(now.plusSeconds(86399),ZoneOffset.UTC)).require("dev-source-tj-001",TjCandidates.Purpose.SONG)).isNotNull();
        error(()->service(Clock.fixed(now.plusSeconds(86400),ZoneOffset.UTC)).require("dev-source-tj-001",TjCandidates.Purpose.SONG),"SOURCE_TOKEN_EXPIRED",409);
    }
    @Test void futureAndExcessiveValidityAreRejected(){
        error(()->service(Clock.fixed(now.minusSeconds(1),ZoneOffset.UTC)).require("dev-source-tj-001",TjCandidates.Purpose.SONG),"SOURCE_TOKEN_INVALID",400);
        var bad=new TjCandidates(token->new CandidateVerifier.Verified("test",CandidateVerifier.Brand.TJ,"1","곡","가수",now,now.plusSeconds(86401)),clock);
        error(()->bad.require("proof",TjCandidates.Purpose.SONG),"SOURCE_TOKEN_INVALID",400);
    }
    @Test void defaultConfigurationFailsClosed(){
        try(var context=new AnnotationConfigApplicationContext(CandidateConfiguration.class)){
            error(()->context.getBean(TjCandidates.class).require("dev-source-tj-001",TjCandidates.Purpose.SONG),"CANDIDATE_VERIFICATION_UNAVAILABLE",503);
        }
    }
    @Test void explicitDevAndFixtureProfilesEnableSyntheticCandidates(){
        try(var context=new AnnotationConfigApplicationContext()){
            context.getEnvironment().setActiveProfiles("dev","candidate-fixtures");context.register(CandidateConfiguration.class);context.refresh();
            assertThat(context.getBean(TjCandidates.class).require("dev-source-tj-001",TjCandidates.Purpose.SONG).provider()).isEqualTo("DEVELOPMENT_FIXTURE");
        }
    }
    @Test void unsafeProfileCombinationsFailStartup(){
        for(String[] profiles:new String[][]{{"candidate-fixtures"},{"dev","candidate-fixtures","prod"},{"dev","candidate-fixtures","production"}}){
            try(var context=new AnnotationConfigApplicationContext()){
                context.getEnvironment().setActiveProfiles(profiles);context.register(CandidateConfiguration.class);
                assertThatThrownBy(context::refresh).hasRootCauseInstanceOf(IllegalStateException.class);
            }
        }
    }
    @Test void devProfileAloneDoesNotEnableFixtures(){
        try(var context=new AnnotationConfigApplicationContext()){
            context.getEnvironment().setActiveProfiles("dev");context.register(CandidateConfiguration.class);context.refresh();
            error(()->context.getBean(TjCandidates.class).require("dev-source-tj-001",TjCandidates.Purpose.SONG),"CANDIDATE_VERIFICATION_UNAVAILABLE",503);
        }
    }
}
