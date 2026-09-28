package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.LinkedMultiValueMap;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Same API and historical-name scenario on H2 and fully migrated MySQL. */
public final class ConditionDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private ConditionDatabaseChecks(){}
    public static void verify(JdbcTemplate db,ConditionService definitions,RecordingDrafts drafts,RecordingEditing editing,String auth,String device,UUID owner){
        var defaults=definitions.list(auth,device,new LinkedMultiValueMap<>());assertThat(defaults.count()).isEqualTo(4);
        String good=(String)defaults.items().stream().filter(v->v.get("code").equals("GOOD")).findFirst().orElseThrow().get("id");
        UUID recording=UUID.randomUUID();drafts.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",recording.toString(),"metadata_state","DRAFT","recorded_at","2026-09-28T07:00:00Z","timezone_id","UTC","timezone_offset_minutes",0)));
        edit(editing,auth,device,recording,1,"GOOD");
        definitions.rename(auth,device,UUID.randomUUID().toString(),good,JSON.writeValueAsString(Map.of("base_revision",1,"name","힘남")));
        assertThat(snapshot(db,recording)).isEqualTo("좋음");edit(editing,auth,device,recording,2,"GOOD");assertThat(snapshot(db,recording)).isEqualTo("좋음");
        edit(editing,auth,device,recording,3,null);edit(editing,auth,device,recording,4,"GOOD");assertThat(snapshot(db,recording)).isEqualTo("힘남");
        long seq=db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner));String archiveOp=UUID.randomUUID().toString();
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_condition_archive CHECK(entity_type<>'CONDITION' OR revision<3)");
        assertThatThrownBy(()->definitions.archive(auth,device,archiveOp,good,"{\"base_revision\":2}")).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(db.queryForObject("SELECT archived_at FROM condition_definition WHERE id=?",java.sql.Timestamp.class,bytes(UUID.fromString(good)))).isNull();assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(seq);
        String product=db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());db.execute("ALTER TABLE change_log DROP "+(product.equals("MySQL")?"CHECK":"CONSTRAINT")+" reject_condition_archive");
        var archived=definitions.archive(auth,device,archiveOp,good,"{\"base_revision\":2}");assertThat(archived.status()).isEqualTo(200);assertThat(JSON.readTree(definitions.archive(auth,device,archiveOp,good,"{\"base_revision\":2}").body())).isEqualTo(JSON.readTree(archived.body()));
        edit(editing,auth,device,recording,5,"GOOD");assertThat(snapshot(db,recording)).isEqualTo("힘남");
        if(product.equals("MySQL")){db.update("UPDATE recording SET condition_name_snapshot='tamper' WHERE id=?",bytes(recording));assertThat(snapshot(db,recording)).isEqualTo("힘남");}
        edit(editing,auth,device,recording,6,null);
        assertThatThrownBy(()->edit(editing,auth,device,recording,7,"GOOD")).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("CONDITION_ARCHIVED"));
        UUID custom=UUID.randomUUID();String create=JSON.writeValueAsString(Map.of("id",custom.toString(),"name","힘남")),op=UUID.randomUUID().toString();var made=definitions.create(auth,device,op,create);assertThat(made.status()).isEqualTo(201);assertThat(JSON.readTree(made.body()).get("code").asText()).isEqualTo(custom.toString());assertThat(JSON.readTree(definitions.create(auth,device,op,create).body())).isEqualTo(JSON.readTree(made.body()));
        edit(editing,auth,device,recording,7,custom.toString());assertThat(snapshot(db,recording)).isEqualTo("힘남");
        String emoji="😀".repeat(50);definitions.rename(auth,device,UUID.randomUUID().toString(),custom.toString(),JSON.writeValueAsString(Map.of("base_revision",1,"name",emoji)));
        assertThat(snapshot(db,recording)).isEqualTo("힘남");edit(editing,auth,device,recording,8,null);edit(editing,auth,device,recording,9,custom.toString());assertThat(snapshot(db,recording)).isEqualTo(emoji);
        var params=new LinkedMultiValueMap<String,String>();params.add("state","ARCHIVED");assertThat(definitions.list(auth,device,params).count()).isEqualTo(1);
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            var start=new java.util.concurrent.CountDownLatch(1);java.util.concurrent.Callable<String> task=()->{start.await();try{return Integer.toString(definitions.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",UUID.randomUUID().toString(),"name","race"))).status());}catch(com.ksh321.songrecord.api.web.ApiException e){return e.code();}};
            var a=pool.submit(task);var b=pool.submit(task);start.countDown();assertThat(List.of(a.get(20,java.util.concurrent.TimeUnit.SECONDS),b.get(20,java.util.concurrent.TimeUnit.SECONDS))).containsExactlyInAnyOrder("201","CONDITION_NAME_IN_USE");
        }catch(Exception e){throw new AssertionError(e);}
    }
    private static void edit(RecordingEditing editing,String auth,String device,UUID id,int revision,String code){var body=new LinkedHashMap<String,Object>();body.put("base_revision",revision);body.put("condition_code",code);assertThat(editing.patch(auth,device,UUID.randomUUID().toString(),id.toString(),JSON.writeValueAsString(body)).status()).isEqualTo(200);}
    private static String snapshot(JdbcTemplate db,UUID id){return db.queryForObject("SELECT condition_name_snapshot FROM recording WHERE id=?",String.class,bytes(id));}
}
