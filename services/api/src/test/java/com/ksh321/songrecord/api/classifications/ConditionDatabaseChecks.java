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
        assertThat(definitions.list(auth,device,new LinkedMultiValueMap<>()).items()).isEqualTo(ConditionCatalog.ITEMS);
        var before=db.queryForList("SELECT * FROM condition_definition WHERE user_id=? ORDER BY id",bytes(owner));
        long seq=db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner));
        for(Runnable attempt:List.<Runnable>of(
            ()->definitions.create(auth,device,UUID.randomUUID().toString(),"{}"),
            ()->definitions.rename(auth,device,null,"invalid","not json"),
            ()->definitions.archive(auth,device,null,UUID.randomUUID().toString(),null)))
            assertThatThrownBy(attempt::run).isInstanceOfSatisfying(ApiException.class,e->{assertThat(e.status().value()).isEqualTo(405);assertThat(e.code()).isEqualTo("CONDITION_CATALOG_READ_ONLY");});
        assertThat(db.queryForList("SELECT * FROM condition_definition WHERE user_id=? ORDER BY id",bytes(owner))).usingRecursiveComparison().isEqualTo(before);
        assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(seq);
        String oldCode=db.queryForObject("SELECT condition_code FROM recording WHERE id=?",String.class,bytes(legacy));
        String oldName=snapshot(db,legacy);
        // Omitted condition retains a legacy relation and historical name.
        editing.patch(auth,device,UUID.randomUUID().toString(),legacy.toString(),"{\"base_revision\":1,\"note\":\"kept\"}");
        assertThat(snapshot(db,legacy)).isEqualTo(oldName);
        assertThat(db.queryForObject("SELECT condition_code FROM recording WHERE id=?",String.class,bytes(legacy))).isEqualTo(oldCode);
        assertThatThrownBy(()->edit(editing,auth,device,legacy,2,oldCode)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(400));
        String op=UUID.randomUUID().toString(),body="{\"base_revision\":2,\"condition_code\":\"GOOD\"}";
        var result=editing.patch(auth,device,op,legacy.toString(),body);
        assertThat(snapshot(db,legacy)).isEqualTo("좋음");
        assertThat(editing.patch(auth,device,op,legacy.toString(),body)).isEqualTo(result);
        assertThat(db.queryForObject("SELECT condition_name_snapshot FROM recording_condition_history WHERE user_id=? AND recording_id=? AND source_revision=2",String.class,bytes(owner),bytes(legacy))).isEqualTo(oldName);
        assertThat(db.queryForObject("SELECT condition_code FROM recording_condition_history WHERE user_id=? AND recording_id=? AND source_revision=2",String.class,bytes(owner),bytes(legacy))).isEqualTo(oldCode);
        edit(editing,auth,device,legacy,3,"GOOD");assertThat(snapshot(db,legacy)).isEqualTo("좋음");
        edit(editing,auth,device,legacy,4,null);assertThat(snapshot(db,legacy)).isNull();
        // Failure after history insertion must roll back history, metadata and receipt atomically.
        edit(editing,auth,device,legacy,5,"BAD");
        String product=db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_condition_replacement CHECK(entity_type<>'RECORDING' OR revision<7)");
        String retryOp=UUID.randomUUID().toString(),retryBody="{\"base_revision\":6,\"condition_code\":null}";
        assertThatThrownBy(()->editing.patch(auth,device,retryOp,legacy.toString(),retryBody)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(snapshot(db,legacy)).isEqualTo("안 좋음");
        assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_condition_history WHERE recording_id=? AND source_revision=6",Integer.class,bytes(legacy))).isZero();
        db.execute("ALTER TABLE change_log DROP "+(product.equals("MySQL")?"CHECK":"CONSTRAINT")+" reject_condition_replacement");
        assertThat(editing.patch(auth,device,retryOp,legacy.toString(),retryBody).status()).isEqualTo(200);
        // Concurrent writes cannot reopen a read-only catalog.
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            java.util.concurrent.Callable<String> call=()->{try{definitions.create(auth,device,UUID.randomUUID().toString(),"{}");return "unexpected";}catch(ApiException e){return e.code();}};
            var a=pool.submit(call);var c=pool.submit(call);
            assertThat(List.of(a.get(),c.get())).containsOnly("CONDITION_CATALOG_READ_ONLY");
        }catch(Exception e){throw new AssertionError(e);}
        assertThat(db.queryForList("SELECT * FROM condition_definition WHERE user_id=? ORDER BY id",bytes(owner))).usingRecursiveComparison().isEqualTo(before);
    }
    private static void edit(RecordingEditing editing,String auth,String device,UUID id,int revision,String code){var body=new LinkedHashMap<String,Object>();body.put("base_revision",revision);body.put("condition_code",code);assertThat(editing.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(body)).status()).isEqualTo(200);}
    private static String snapshot(JdbcTemplate db,UUID id){return db.queryForObject("SELECT condition_name_snapshot FROM recording WHERE id=?",String.class,bytes(id));}
}
