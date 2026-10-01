package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.sql.SQLException;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.util.MultiValueMap;
import tools.jackson.databind.json.JsonMapper;

public final class ChangeQueries {
    private final AccountAccess access;private final ChangeReadView view;
    private final JsonMapper json=new JsonMapper();
    public ChangeQueries(AccountAccess access,ChangeReadView view){this.access=access;this.view=view;}
    public Map<String,Object> get(String authorization,String device,MultiValueMap<String,String> query)throws SQLException {
        var account=access.authenticate(authorization,device);
        if(query.keySet().stream().anyMatch(k->!Set.of("after_seq","limit").contains(k))
                ||query.values().stream().anyMatch(v->v==null||v.size()!=1||v.getFirst()==null))throw invalid();
        long after;int limit=50;
        try {
            String value=query.getFirst("after_seq");
            if(value==null||!value.matches("0|[1-9][0-9]{0,18}"))throw invalid();
            after=Long.parseLong(value);
            if(query.containsKey("limit")) {
                String count=query.getFirst("limit");if(!count.matches("[1-9][0-9]{0,2}"))throw invalid();
                limit=Integer.parseInt(count);if(limit>100)throw invalid();
            }
        }catch(NumberFormatException e){throw invalid();}
        var page=view.read(account,after,limit);
        Map<String,Object> body=Map.of("after_seq",page.afterSequence(),"next_seq",page.nextSequence(),"head_seq",page.head(),"has_more",page.hasMore(),
            "changes",page.entries().stream().map(e->Map.of("change_seq",e.sequence(),"entity_type",e.change().entity().name(),
                "entity_id",e.change().id().toString(),"revision",e.change().revision(),"operation",e.change().operation().name(),
                "payload",json.readTree(e.change().payload()))).toList());
        access.revalidate(account);
        return body;
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"INVALID_CURSOR","동기화 위치와 개수를 확인해 주세요.",false,Map.of());}
}
