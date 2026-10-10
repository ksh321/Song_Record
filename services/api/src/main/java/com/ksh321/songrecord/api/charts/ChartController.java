package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
@RestController @Profile("!bootstrap") @RequestMapping("/v1/charts/popular")
public class ChartController {
    private final AccountAccess access;private final ChartResults results;
    public ChartController(AccountAccess access,ChartResults results){this.access=access;this.results=results;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String,Object>> read(@RequestHeader(value="Authorization",required=false)String auth,@RequestHeader(value="X-Device-Id",required=false)String device,@RequestParam MultiValueMap<String,String> params){
        var account=access.authenticate(auth,device);
        if(params.size()!=2 || !params.keySet().equals(Set.of("brand","period")) || params.values().stream().anyMatch(v->v.size()!=1))throw new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","차트 브랜드와 기간을 확인해 주세요.",false,Map.of());
        return ResponseEntity.ok().header("Cache-Control","no-store").body(results.read(account,ChartScope.parse(params.getFirst("brand"),params.getFirst("period"))));
    }
}
