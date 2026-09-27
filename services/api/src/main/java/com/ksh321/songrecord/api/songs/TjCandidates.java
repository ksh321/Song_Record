package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.Map;
import org.springframework.http.HttpStatus;

/** Registration boundary. No client brand, number or source-title override is accepted here. */
public final class TjCandidates {
    public enum Purpose { SONG, PLAYLIST }
    private final CandidateVerifier verifier;
    private final Clock clock;
    public TjCandidates(CandidateVerifier verifier,Clock clock){this.verifier=verifier;this.clock=clock;}
    public CandidateVerifier.Verified require(String sourceToken,Purpose purpose) {
        java.util.Objects.requireNonNull(purpose);
        if(sourceToken==null || sourceToken.isBlank() || sourceToken.length()>8192)throw invalid();
        var candidate=verifier.verify(sourceToken);
        if(candidate==null)throw new IllegalStateException("Verifier returned no candidate");
        var now=clock.instant();
        if(candidate.issuedAt().isAfter(now) || !candidate.expiresAt().isAfter(candidate.issuedAt())
                || Duration.between(candidate.issuedAt(),candidate.expiresAt()).compareTo(Duration.ofHours(24))>0)throw invalid();
        if(!now.isBefore(candidate.expiresAt()))throw new ApiException(HttpStatus.CONFLICT,"SOURCE_TOKEN_EXPIRED",
                "검색 결과를 다시 확인해 주세요.",false,Map.of());
        if(candidate.brand()!=CandidateVerifier.Brand.TJ)throw new ApiException(HttpStatus.BAD_REQUEST,
                purpose==Purpose.PLAYLIST?"PLAYLIST_TJ_REQUIRED":"SONG_TJ_REQUIRED","TJ 검색 결과를 선택해 주세요.",false,Map.of());
        return candidate;
    }
    static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"SOURCE_TOKEN_INVALID","검색 결과를 다시 선택해 주세요.",false,Map.of());}
    static ApiException unavailable(){return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"CANDIDATE_VERIFICATION_UNAVAILABLE","검색 후보를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.",true,Map.of());}
}
