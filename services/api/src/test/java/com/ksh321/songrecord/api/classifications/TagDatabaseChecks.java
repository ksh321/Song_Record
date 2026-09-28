package com.ksh321.songrecord.api.classifications;

import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.LinkedMultiValueMap;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

/** Runs identically with H2 and MySQL's generated active-name key and historical-link triggers. */
public final class TagDatabaseChecks {
    private static final JsonMapper JSON=new JsonMapper();
    private TagDatabaseChecks(){}
    public static void verify(JdbcTemplate db,TagService tags,RecordingDrafts drafts,RecordingEditing editing,String auth,String device,UUID owner){
        UUID tag=UUID.randomUUID(),recording=UUID.randomUUID();String op=UUID.randomUUID().toString();
        String create=JSON.writeValueAsString(Map.of("id",tag.toString(),"name","  HELLO  "));var result=tags.create(auth,device,op,create);assertThat(result.status()).isEqualTo(201);
        assertThat(JSON.readTree(result.body()).get("name").asText()).isEqualTo("HELLO");assertThat(JSON.readTree(tags.create(auth,device,op,create).body())).isEqualTo(JSON.readTree(result.body()));
        assertThat(tags.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",tag.toString(),"name","ignored"))).status()).isEqualTo(200);
        assertThat(db.queryForObject("SELECT name FROM tag WHERE id=?",String.class,bytes(tag))).isEqualTo("HELLO");
        assertThatThrownBy(()->tags.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",UUID.randomUUID().toString(),"name","hello")))).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("TAG_NAME_IN_USE"));
        drafts.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",recording.toString(),"metadata_state","DRAFT","recorded_at","2026-09-28T07:00:00Z","timezone_id","UTC","timezone_offset_minutes",0)));
        editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(Map.of("base_revision",1,"tag_ids",List.of(tag.toString()))));
        var recordingBefore=db.queryForMap("SELECT * FROM recording WHERE id=?",bytes(recording));
        long receiptBefore=count(db,"mutation_receipt"),seq=db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner));
        String rename=JSON.writeValueAsString(Map.of("base_revision",1,"name","renamed")),renameOp=UUID.randomUUID().toString();
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_tag_edit CHECK(entity_type<>'TAG' OR revision=1)");
        assertThatThrownBy(()->tags.rename(auth,device,renameOp,tag.toString(),rename)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(db.queryForObject("SELECT name FROM tag WHERE id=?",String.class,bytes(tag))).isEqualTo("HELLO");assertThat(count(db,"mutation_receipt")).isEqualTo(receiptBefore);
        assertThat(db.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(seq);
        String product=db.execute((java.sql.Connection c)->c.getMetaData().getDatabaseProductName());db.execute("ALTER TABLE change_log DROP "+(product.equals("MySQL")?"CHECK":"CONSTRAINT")+" reject_tag_edit");
        assertThat(tags.rename(auth,device,renameOp,tag.toString(),rename).status()).isEqualTo(200);
        assertThat(db.queryForObject("SELECT normalized_name_key FROM tag WHERE id=?",byte[].class,bytes(tag))).isEqualTo("renamed".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        assertThat(db.queryForObject("SELECT name_snapshot FROM recording_tag WHERE tag_id=?",String.class,bytes(tag))).isEqualTo("HELLO");
        String archiveOp=UUID.randomUUID().toString(),archive="{\"base_revision\":2}";
        var archived=tags.archive(auth,device,archiveOp,tag.toString(),archive);assertThat(archived.status()).isEqualTo(200);assertThat(JSON.readTree(tags.archive(auth,device,archiveOp,tag.toString(),archive).body())).isEqualTo(JSON.readTree(archived.body()));
        assertThat(db.queryForMap("SELECT * FROM recording WHERE id=?",bytes(recording))).usingRecursiveComparison().isEqualTo(recordingBefore);
        assertThat(db.queryForObject("SELECT name_snapshot FROM recording_tag WHERE tag_id=?",String.class,bytes(tag))).isEqualTo("HELLO");
        assertThat(tags.list(auth,device,new LinkedMultiValueMap<>()).count()).isZero();var all=new LinkedMultiValueMap<String,String>();all.add("state","ARCHIVED");assertThat(tags.list(auth,device,all).count()).isEqualTo(1);
        assertThatThrownBy(()->tags.rename(auth,device,UUID.randomUUID().toString(),tag.toString(),"{\"base_revision\":3,\"name\":\"changed\"}")).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("TAG_ARCHIVED"));
        UUID replacement=UUID.randomUUID();assertThat(tags.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",replacement.toString(),"name","RENAMED"))).status()).isEqualTo(201);
        // Existing archived relationships survive resubmission; detached ones cannot be newly selected.
        editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(Map.of("base_revision",2,"tag_ids",List.of(tag.toString()))));
        editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),"{\"base_revision\":3,\"tag_ids\":[]}");
        assertThatThrownBy(()->editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(Map.of("base_revision",4,"tag_ids",List.of(tag.toString()))))).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("TAG_ARCHIVED"));
        try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){
            var start=new java.util.concurrent.CountDownLatch(1);
            java.util.concurrent.Callable<String> task=()->{start.await();try{return Integer.toString(tags.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",UUID.randomUUID().toString(),"name","race"))).status());}catch(com.ksh321.songrecord.api.web.ApiException e){return e.code();}};
            var a=pool.submit(task);var b=pool.submit(task);start.countDown();assertThat(List.of(a.get(20,java.util.concurrent.TimeUnit.SECONDS),b.get(20,java.util.concurrent.TimeUnit.SECONDS))).containsExactlyInAnyOrder("201","TAG_NAME_IN_USE");
        }catch(Exception e){throw new AssertionError(e);}
        var page=new LinkedMultiValueMap<String,String>();page.add("state","ALL");page.add("limit","1");var ids=new HashSet<String>();String cursor=null;
        do{if(cursor!=null)page.set("cursor",cursor);var p=tags.list(auth,device,page);assertThat(p.count()).isEqualTo(3);assertThat(ids.add((String)p.items().getFirst().get("id"))).isTrue();cursor=p.next_cursor();}while(cursor!=null);
        assertThat(ids).hasSize(3);
        UUID unicode=UUID.randomUUID();String emoji="😀".repeat(50);
        assertThat(tags.create(auth,device,UUID.randomUUID().toString(),JSON.writeValueAsString(Map.of("id",unicode.toString(),"name",emoji))).status()).isEqualTo(201);
        editing.patch(auth,device,UUID.randomUUID().toString(),recording.toString(),JSON.writeValueAsString(Map.of("base_revision",4,"tag_ids",List.of(unicode.toString()))));
        assertThat(db.queryForObject("SELECT name_snapshot FROM recording_tag WHERE tag_id=?",String.class,bytes(unicode))).isEqualTo(emoji);
    }
    private static long count(JdbcTemplate db,String table){return db.queryForObject("SELECT COUNT(*) FROM "+table,Long.class);}
}
