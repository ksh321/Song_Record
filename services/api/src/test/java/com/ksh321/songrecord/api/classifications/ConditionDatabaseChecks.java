package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.recordings.*;
import com.ksh321.songrecord.api.web.ApiException;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.LinkedMultiValueMap;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** D06: identical H2/MySQL application checks; real migration/trigger checks are additional. */
public final class ConditionDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private ConditionDatabaseChecks(){}
    public static void verify(JdbcTemplate db,ConditionService definitions,RecordingDrafts drafts,RecordingEditing editing,String auth,String device,UUID owner,UUID legacy){
        var listed=definitions.list(auth,device,new LinkedMultiValueMap<>()).items();
        assertThat(listed).noneMatch(item->item.get("archived_at")!=null);
        UUID custom=UUID.randomUUID();
        String createOp=UUID.randomUUID().toString(),createBody=JSON.writeValueAsString(Map.of("id",custom.toString(),"name","새 컨디션"));
        var created=definitions.create(auth,device,createOp,createBody);
        assertThat(created.status()).isEqualTo(201);
        assertThat(definitions.create(auth,device,createOp,createBody)).isEqualTo(created);
        assertThatThrownBy(()->definitions.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",UUID.randomUUID().toString(),"name","새 컨디션"))))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CONDITION_NAME_IN_USE"));
        String oldCode=db.queryForObject("SELECT condition_code FROM recording WHERE id=?",String.class,bytes(legacy));
        String oldName=snapshot(db,legacy);
        // Omitted condition retains a legacy relation and historical name.
        editing.patch(auth,device,UUID.randomUUID().toString(),legacy.toString(),"{\"base_revision\":1,\"note\":\"kept\"}");
        assertThat(snapshot(db,legacy)).isEqualTo(oldName);
        assertThat(db.queryForObject("SELECT condition_code FROM recording WHERE id=?",String.class,bytes(legacy))).isEqualTo(oldCode);
        // Keeping the same archived reference preserves its historical name.
        edit(editing,auth,device,legacy,2,oldCode);
        assertThat(snapshot(db,legacy)).isEqualTo(oldName);
        assertThatThrownBy(()->edit(editing,auth,device,legacy,3,"GOOD"))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CONDITION_ARCHIVED"));
        String op=UUID.randomUUID().toString(),body=JSON.writeValueAsString(Map.of("base_revision",3,"condition_code",custom.toString()));
        var result=editing.patch(auth,device,op,legacy.toString(),body);
        assertThat(snapshot(db,legacy)).isEqualTo("새 컨디션");
        assertThat(editing.patch(auth,device,op,legacy.toString(),body)).isEqualTo(result);
        assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording_condition_history WHERE user_id=? AND recording_id=? AND source_revision=3",String.class,bytes(owner),bytes(legacy))).isEqualTo(oldName);
        definitions.rename(auth,device,UUID.randomUUID().toString(),custom.toString(),"{\"base_revision\":1,\"name\":\"변경한 컨디션\"}");
        assertThat(snapshot(db,legacy)).isEqualTo("새 컨디션");
        edit(editing,auth,device,legacy,4,custom.toString());
        assertThat(snapshot(db,legacy)).isEqualTo("새 컨디션");
        definitions.archive(auth,device,UUID.randomUUID().toString(),custom.toString(),"{\"base_revision\":2}");
        edit(editing,auth,device,legacy,5,custom.toString());
        assertThat(snapshot(db,legacy)).isEqualTo("새 컨디션");
        edit(editing,auth,device,legacy,6,null);
        assertThatThrownBy(()->edit(editing,auth,device,legacy,7,custom.toString()))
            .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CONDITION_ARCHIVED"));
        edit(editing,auth,device,legacy,7,"BAD");
        // Roll back history, metadata and receipt together on a downstream failure.
        String product=db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_condition_replacement CHECK(entity_type<>'RECORDING' OR revision<9)");
        String retryOp=UUID.randomUUID().toString(),retryBody="{\"base_revision\":8,\"condition_code\":null}";
        assertThatThrownBy(()->editing.patch(auth,device,retryOp,legacy.toString(),retryBody)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(snapshot(db,legacy)).isEqualTo("안 좋음");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE recording_id=? AND source_revision=8",Integer.class,bytes(legacy))).isZero();
        db.execute("ALTER TABLE change_log DROP "+(product.equals("MySQL")?"CHECK":"CONSTRAINT")+" reject_condition_replacement");
        assertThat(editing.patch(auth,device,retryOp,legacy.toString(),retryBody).status()).isEqualTo(200);
        UUID raced=UUID.randomUUID();
        definitions.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",raced.toString(),"name","동시 변경 전")));
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            java.util.concurrent.Callable<String> call=()->{try{
                definitions.rename(auth,device,UUID.randomUUID().toString(),raced.toString(),"{\"base_revision\":1,\"name\":\"동시 변경 후\"}");
                return "OK";
            }catch(ApiException e){return e.code();}};
            var a=pool.submit(call);var c=pool.submit(call);
            assertThat(List.of(a.get(),c.get())).containsExactlyInAnyOrder("OK","REVISION_CONFLICT");
        }catch(Exception e){throw new AssertionError(e);}
    }
    private static void edit(RecordingEditing editing,String auth,String device,UUID id,int revision,String code){var body=new LinkedHashMap<String,Object>();body.put("base_revision",revision);body.put("condition_code",code);assertThat(editing.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(body)).status()).isEqualTo(200);}
    private static String snapshot(JdbcTemplate db,UUID id){return db.queryForObject("SELECT condition_name_snapshot FROM recording WHERE id=?",String.class,bytes(id));}
}
