package com.ksh321.songrecord.api.sync;

import java.sql.SQLException;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.http.*;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/sync/changes")
public class ChangeController {
    private final ChangeQueries queries;
    public ChangeController(ChangeQueries queries){this.queries=queries;}
    @GetMapping(produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String,Object>> get(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Device-Id",required=false) String device,@RequestParam MultiValueMap<String,String> query)throws SQLException {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(queries.get(auth,device,query));
    }
}
