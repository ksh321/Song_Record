package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import java.util.*;
public final class KaraokeResults {
    @FunctionalInterface public interface Matches {Map<String,UUID> activeTj(UUID owner,List<String> numbers);}
    private final AccountAccess access;private final KaraokeSearch search;private final SourceTokens tokens;private final Matches matches;
    public KaraokeResults(AccountAccess access,KaraokeSearch search,SourceTokens tokens,Matches matches){this.access=access;this.search=search;this.tokens=tokens;this.matches=matches;}
    public List<Map<String,Object>> find(AccountAccess.Account account,Brand brand,MananaSearchAdapter.Kind kind,String query){
        var principal=access.revalidate(account);tokens.requireAvailable();var candidates=search.search(account,brand,kind,query);
        var matched=brand==Brand.TJ && !candidates.isEmpty()?matches.activeTj(principal.userId(),candidates.stream().map(MananaSearchAdapter.Candidate::number).toList()):Map.<String,UUID>of();
        access.revalidate(account);var rows=new ArrayList<Map<String,Object>>();
        for(var c:candidates){var proof=tokens.issueProof(c);var row=new LinkedHashMap<String,Object>();row.put("brand",c.brand().name());row.put("number",c.number());row.put("title",c.title());row.put("artist",c.artist());row.put("provider",c.provider());row.put("source_ref",c.sourceRef());row.put("source_token",tokens.encode(proof));row.put("expires_at",proof.expiresAt().toString());var id=matched.get(c.number());row.put("matched_song_id",brand==Brand.TJ && id!=null?id.toString():null);rows.add(Collections.unmodifiableMap(row));}
        return List.copyOf(rows);
    }
}
