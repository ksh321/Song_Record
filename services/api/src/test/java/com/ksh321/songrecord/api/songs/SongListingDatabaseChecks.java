package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.pagination.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
import static org.assertj.core.api.Assertions.*;

/** Runs unchanged on H2 and real MySQL against the production list SQL. */
public final class SongListingDatabaseChecks {
    private SongListingDatabaseChecks() {}
    public static void verify(JdbcTemplate jdbc,KeysetPages pages,AccountAccess.Account account,UUID owner,UUID device) throws Exception {
        var fixture=new JsonMapper().readTree(Files.readString(Path.of("../../fixtures/songs/list-order.json")));
        for(var row:fixture.get("rows")){
            UUID id=UUID.fromString(row.get("id").asText());String title=row.get("title").asText(),artist=row.get("artist").asText();
            jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,song_tier,lifecycle_state,revision,created_at,updated_at) VALUES(?,?,'MANUAL',?,?,'NORMAL','',?,'ACTIVE',1,?,?)",
                    bytes(id),bytes(owner),title,artist,row.get("tier").isNull()?null:row.get("tier").asText(),time(row.get("created_at").asText()),time(row.get("created_at").asText()));
            insert(jdbc,owner,id,title,artist);
            if(!row.get("latest_recorded_at").isNull())recording(jdbc,owner,device,id,row.get("latest_recorded_at").asText(),"SAVED","ACTIVE");
        }
        UUID first=UUID.fromString(fixture.get("rows").get(0).get("id").asText());
        recording(jdbc,owner,device,first,"2030-01-01T00:00:00Z","DRAFT","ACTIVE");
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED"))recording(jdbc,owner,device,first,"2030-01-01T00:00:00Z","SAVED",state);
        recording(jdbc,owner,device,null,"2030-01-01T00:00:00Z","SAVED","ACTIVE");
        UUID other=UUID.randomUUID();jdbc.update("INSERT INTO app_user(id) VALUES(?)",bytes(other));
        add(jdbc,other,UUID.randomUUID(),"가2","a","ACTIVE");
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED"))add(jdbc,owner,UUID.randomUUID(),"가2","a",state);
        for(var view:SongListRules.View.values())for(var sort:SongListRules.Sort.values()){
            var query=SongListRules.Query.parse("",sort.name(),view.name(),2);var expected=new ArrayList<String>();
            fixture.get("expected").get(view.name()).get(sort.name()).forEach(n->expected.add(n.asText()));
            var actual=new ArrayList<String>();String cursor=null;
            do{
                var page=pages.query(account,query.cursorQuery(),cursor,new SongListing.Source(query));
                assertThat(page.count()).isEqualTo(8);assertThat(page.items()).hasSize(2);
                for(var item:page.items()){
                    actual.add((String)item.get("id"));assertThat(item.get("version_code")).isEqualTo("NORMAL");
                    if(item.get("id").equals(first.toString()))assertThat(item.get("latest_recorded_at")).isEqualTo("2026-02-03T00:00:00Z");
                }
                assertThat(actual.size()).isLessThanOrEqualTo(8);cursor=page.next_cursor();
            }while(cursor!=null);
            assertThat(actual).as(view+"/"+sort).containsExactlyElementsOf(expected);
        }
        var search=SongListRules.Query.parse(" \u3000A ","TITLE",null,100);
        assertThat(pages.query(account,search.cursorQuery(),null,new SongListing.Source(search)).items()).extracting(x->x.get("id"))
                .containsExactly(fixture.get("rows").get(1).get("id").asText(),fixture.get("rows").get(5).get("id").asText(),fixture.get("rows").get(7).get("id").asText(),fixture.get("rows").get(3).get("id").asText());
        UUID literal=UUID.randomUUID();add(jdbc,owner,literal,"%_!\\","É가","ACTIVE");
        for(String q:List.of("%","_","!","\\","가","É")){
            var query=SongListRules.Query.parse(q,null,null,100);
            var page=pages.query(account,query.cursorQuery(),null,new SongListing.Source(query));
            if(!q.equals("가"))assertThat(page.items()).extracting(x->x.get("id")).containsExactly(literal.toString());
            else assertThat(page.items()).extracting(x->x.get("id")).contains(literal.toString());
        }
        var empty=SongListRules.Query.parse("does-not-exist",null,null,50);
        var page=pages.query(account,empty.cursorQuery(),null,new SongListing.Source(empty));
        assertThat(page.items()).isEmpty();assertThat(page.count()).isZero();assertThat(page.next_cursor()).isNull();
    }
    public static void add(JdbcTemplate jdbc,UUID owner,UUID id,String title,String artist,String state){
        jdbc.update("INSERT INTO song(id,user_id,source_type,title,artist,version_code,note,lifecycle_state,revision,created_at,updated_at,deleted_at) VALUES(?,?,'MANUAL',?,?,'NORMAL','',?,1,?,?,?)",
                bytes(id),bytes(owner),title,artist,state,time("2026-01-01T00:00:00Z"),time("2026-01-01T00:00:00Z"),state.equals("ACTIVE")?null:time("2026-01-02T00:00:00Z"));
        insert(jdbc,owner,id,title,artist);
    }
    private static void recording(JdbcTemplate jdbc,UUID owner,UUID device,UUID song,String time,String metadata,String state){
        jdbc.update("INSERT INTO recording(id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state,lifecycle_state,deleted_at) VALUES(?,?,?,?,'곡','가수','NORMAL','ORIGINAL',0,'',?,'UTC',0,?,?,?)",
                bytes(UUID.randomUUID()),bytes(owner),bytes(device),song==null?null:bytes(song),time(time),metadata,state,state.equals("ACTIVE")?null:time(time));
    }
    private static LocalDateTime time(String instant){return LocalDateTime.ofInstant(Instant.parse(instant),ZoneOffset.UTC);}
}
