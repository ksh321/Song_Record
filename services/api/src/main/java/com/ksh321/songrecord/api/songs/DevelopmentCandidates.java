package com.ksh321.songrecord.api.songs;

import java.time.*;
import java.util.Map;

/** Synthetic fixtures, never real TJ catalogue results. Constructed only by explicit dev configuration. */
final class DevelopmentCandidates implements CandidateVerifier {
    private final Map<String,Verified> fixtures;
    DevelopmentCandidates(Clock clock) {
        Instant now=clock.instant(),expires=now.plus(Duration.ofHours(24));
        fixtures=Map.of(
            "dev-source-tj-001",new Verified("DEVELOPMENT_FIXTURE",Brand.TJ,"990001","개발 검증 곡","개발 검증 가수",now,expires),
            "dev-source-tj-002",new Verified("DEVELOPMENT_FIXTURE",Brand.TJ,"990002","개발 검증 곡","개발 검증 가수",now,expires),
            "dev-source-ky-001",new Verified("DEVELOPMENT_FIXTURE",Brand.KY,"990001","개발 검증 곡","개발 검증 가수",now,expires));
    }
    public Verified verify(String sourceToken) {
        var result=sourceToken==null?null:fixtures.get(sourceToken);
        if(result==null)throw TjCandidates.invalid();
        return result;
    }
}
