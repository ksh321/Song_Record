package com.ksh321.songrecord.api.karaoke;

import com.ksh321.songrecord.api.songs.CandidateVerifier;
import com.ksh321.songrecord.api.web.ApiException;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Authenticated source proof, with an exact TJ-number refresh outside database locks. */
public final class LiveCandidates implements CandidateVerifier {
    private final SourceTokens tokens;private final KaraokeSearch.Provider provider;
    private final SearchLimit limit;private final Clock clock;
    public LiveCandidates(SourceTokens tokens,KaraokeSearch.Provider provider,SearchLimit limit,Clock clock){
        this.tokens=tokens;this.provider=provider;this.limit=limit;this.clock=clock;
    }
    @Override public Verified verify(String token){return verified(tokens.read(token));}
    @Override public Verified prepare(String token,UUID owner){
        var proof=tokens.read(token);var old=proof.candidate();
        if(old.brand()!=Brand.TJ || clock.instant().isBefore(proof.expiresAt()))return verified(proof);
        if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Source refresh inside transaction");
        limit.acquire(Objects.requireNonNull(owner));
        List<MananaSearchAdapter.Candidate> rows;
        try{rows=provider.search(Brand.TJ,MananaSearchAdapter.Kind.NUMBER,old.number());}
        catch(MananaSearchAdapter.ProviderFailure e){
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"CANDIDATE_VERIFICATION_UNAVAILABLE",
                    "후보를 확인할 수 없습니다. 입력 내용은 유지됩니다.",true,Map.of());
        }
        var matches=rows.stream().filter(c->c.brand()==Brand.TJ && old.number().equals(c.number())).toList();
        if(matches.size()!=1)throw new ApiException(HttpStatus.CONFLICT,"SOURCE_CANDIDATE_NOT_FOUND",
                "같은 TJ 번호를 확인할 수 없습니다. 입력을 유지하고 다시 검색해 주세요.",false,Map.of());
        return verified(tokens.issueProof(matches.getFirst()));
    }
    private static Verified verified(SourceTokens.Proof p){var c=p.candidate();return new Verified(c.provider(),c.brand(),c.number(),c.title(),c.artist(),p.issuedAt(),p.expiresAt());}
}
