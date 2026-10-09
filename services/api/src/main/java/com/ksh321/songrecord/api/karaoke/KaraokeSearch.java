package com.ksh321.songrecord.api.karaoke;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.http.HttpStatus;

public final class KaraokeSearch {
    @FunctionalInterface public interface Provider {List<MananaSearchAdapter.Candidate> search(Brand brand,MananaSearchAdapter.Kind kind,String query);}
    private final AccountAccess access;private final SearchLimit limit;private final Provider provider;
    public KaraokeSearch(AccountAccess access,SearchLimit limit,Provider provider){this.access=access;this.limit=limit;this.provider=provider;}
    public List<MananaSearchAdapter.Candidate> search(AccountAccess.Account account,Brand brand,MananaSearchAdapter.Kind kind,String input){
        var principal=access.revalidate(account);
        var query=input==null?"":input.strip();
        if(brand==null || kind==null || query.isEmpty() || query.codePointCount(0,query.length())>200 || query.codePoints().anyMatch(Character::isISOControl) || kind==MananaSearchAdapter.Kind.NUMBER && !query.matches("[0-9]{1,20}")) throw new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","검색 조건을 확인해 주세요.",false,Map.of());
        limit.acquire(principal.userId());
        List<MananaSearchAdapter.Candidate> result;
        try {result=provider.search(brand,kind,query);}
        catch(MananaSearchAdapter.ProviderFailure e){
            var code=switch(e.kind()){case TIMEOUT->"SEARCH_TIMEOUT";case NETWORK->"SEARCH_NETWORK_UNAVAILABLE";case PROVIDER_STATUS->"SEARCH_PROVIDER_UNAVAILABLE";case INVALID_RESPONSE->"SEARCH_INVALID_RESPONSE";};
            throw new ApiException(e.kind()==MananaSearchAdapter.Failure.TIMEOUT?HttpStatus.GATEWAY_TIMEOUT:HttpStatus.BAD_GATEWAY,code,"외부 검색에 연결할 수 없습니다. 입력 내용은 유지됩니다.",true,Map.of());
        }
        access.revalidate(account);
        return List.copyOf(result);
    }
}
