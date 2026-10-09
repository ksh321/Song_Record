package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.songs.CandidateVerifier.Brand;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/karaoke/search")
public class KaraokeController {
    private final AccountAccess access;private final KaraokeResults results;
    public KaraokeController(AccountAccess access,KaraokeResults results){this.access=access;this.results=results;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String,Object>> search(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestParam MultiValueMap<String,String> params){
        var account=access.authenticate(auth,device);Brand brand;MananaSearchAdapter.Kind kind;
        try {for(var e:params.entrySet())if(!Set.of("brand","kind","q").contains(e.getKey()) || e.getValue().size()!=1)throw new IllegalArgumentException();brand=Brand.valueOf(params.getFirst("brand"));kind=params.containsKey("kind")?MananaSearchAdapter.Kind.valueOf(params.getFirst("kind")):MananaSearchAdapter.Kind.TITLE;}
        catch(IllegalArgumentException|NullPointerException e){throw new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR","검색 조건을 확인해 주세요.",false,Map.of());}
        return ResponseEntity.ok().header("Cache-Control","no-store").body(Map.of("results",results.find(account,brand,kind,params.getFirst("q"))));
    }
}
