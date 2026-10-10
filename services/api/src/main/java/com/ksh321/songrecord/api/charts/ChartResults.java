package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.karaoke.*;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.util.*;
public final class ChartResults {
    private final AccountAccess access;private final ChartQuery query;private final SourceTokens tokens;
    public ChartResults(AccountAccess access,ChartQuery query,SourceTokens tokens){this.access=access;this.query=query;this.tokens=tokens;}
    public Map<String,Object> read(AccountAccess.Account account,ChartScope scope){
        access.revalidate(account);var chart=query.read(scope);if(scope.brand()==Brand.TJ)tokens.requireAvailable();
        var items=new ArrayList<Map<String,Object>>();
        for(var item:chart.items()){
            var row=new LinkedHashMap<String,Object>();row.put("position",item.position());row.put("number",item.number());row.put("title",item.title());row.put("artist",item.artist());
            String token=null;if(scope.brand()==Brand.TJ){var candidate=new MananaSearchAdapter.Candidate(Brand.TJ,item.number(),item.title(),item.artist(),ChartScope.PROVIDER,"manana:tj:"+item.number());token=tokens.encode(tokens.issueProof(candidate));}
            row.put("source_token",token);items.add(Collections.unmodifiableMap(row));
        }
        access.revalidate(account);
        return Map.of("brand",scope.brand().name(),"period",scope.period().name(),"provider",ChartScope.PROVIDER,"source_url",scope.sourceUri().toString(),"fetched_at",chart.fetchedAt().toString(),"revision",chart.revision(),"stale",chart.stale(),"items",List.copyOf(items));
    }
}
