package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.songs.SongQueryKeys;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

class SongEditingTests {
    final SongCreationTests setup=new SongCreationTests();final JsonMapper json=new JsonMapper();UUID song;String path;
    @BeforeEach void open()throws Exception{
        setup.setup();song=setup.id;path="/v1/songs/"+song;
        // H2 VARCHAR counts UTF-16 units; the application and real MySQL check Unicode code points.
        setup.f.jdbc.execute("ALTER TABLE song ALTER COLUMN note VARCHAR(8000)");
        assertThat(setup.postBody(UUID.randomUUID().toString(),setup.body("" )).getStatus()).isEqualTo(201);
    }
    @AfterEach void close()throws Exception{setup.close();}
    MockHttpServletResponse edit(String op,String body)throws Exception{return editAs(path,op,body,setup.f.tokens.accessToken(),setup.f.registration.deviceId());}
    MockHttpServletResponse editAs(String target,String op,String body,String token,UUID device)throws Exception{return setup.mvc.perform(patch(target).header("Authorization","Bearer "+token).header("X-Device-Id",device).header("Idempotency-Key",op).contentType("application/json").content(body)).andReturn().getResponse();}
    MockHttpServletResponse edit(String body)throws Exception{return edit(UUID.randomUUID().toString(),body);}
    MockHttpServletResponse list(String... params)throws Exception{
        var request=get("/v1/songs").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId());
        for(int i=0;i<params.length;i+=2)request.param(params[i],params[i+1]);return setup.mvc.perform(request).andReturn().getResponse();
    }
    long revision(){return setup.f.jdbc.queryForObject("SELECT revision FROM song WHERE id=?",Long.class,SongQueryKeys.bytes(song));}
    @Test void editsEveryFieldAnd2000CodePointNoteWithoutChangingSourceOrPastRecording()throws Exception{
        var db=setup.f.jdbc;UUID recording=UUID.randomUUID();
        db.update("INSERT INTO recording(id,user_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,tier,note,metadata_state,lifecycle_state,recorded_at) VALUES(?,?,?,'과거 제목','과거 가수','LIVE','FEMALE',-2,'D','과거 메모','SAVED','ACTIVE',CURRENT_TIMESTAMP)",SongQueryKeys.bytes(recording),SongQueryKeys.bytes(setup.f.registration.userId()),SongQueryKeys.bytes(song));
        db.update("UPDATE song SET representative_recording_id=? WHERE id=?",SongQueryKeys.bytes(recording),SongQueryKeys.bytes(song));
        var recordingBefore=db.queryForMap("SELECT * FROM recording");var sourceBefore=db.queryForMap("SELECT * FROM song_source");
        var response=edit(json.writeValueAsString(Map.of("base_revision",1,"title"," 새 제목 ","artist"," 새 가수 ","note","😀".repeat(2000),"version_code","MR","tier","A","representative_key_mode","MALE","representative_key_shift",3)));
        assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        var result=json.readTree(response.getContentAsString());assertThat(result.get("revision").asInt()).isEqualTo(2);assertThat(result.get("title").asText()).isEqualTo("새 제목");assertThat(result.get("representative_key_shift").asInt()).isEqualTo(3);
        assertThat(result.get("note").asText().codePointCount(0,result.get("note").asText().length())).isEqualTo(2000);
        assertThat(db.queryForMap("SELECT * FROM recording")).usingRecursiveComparison().isEqualTo(recordingBefore);assertThat(db.queryForMap("SELECT * FROM song_source")).usingRecursiveComparison().isEqualTo(sourceBefore);
        assertThat(db.queryForObject("SELECT representative_recording_id FROM song",byte[].class)).isEqualTo(SongQueryKeys.bytes(recording));
        assertThat(json.readTree(list("q","새 제목").getContentAsString()).get("count").asInt()).isEqualTo(1);
        assertThat(json.readTree(list("q","원본 곡").getContentAsString()).get("count").asInt()).isZero();
        assertThat(db.queryForObject("SELECT payload FROM change_log WHERE change_seq=2",String.class)).contains("새 제목","\"representative_key_mode\":\"MALE\"");
    }
    @Test void omissionKeepsValuesNullClearsAndKeyValidationUsesMergedState()throws Exception{
        assertThat(edit("{\"base_revision\":1,\"note\":\"a\\r\\nb\",\"tier\":\"S\",\"representative_key_mode\":\"FEMALE\",\"representative_key_shift\":-12}").getStatus()).isEqualTo(200);
        var second=edit("{\"base_revision\":2,\"representative_key_shift\":12}");assertThat(second.getStatus()).isEqualTo(200);
        assertThat(json.readTree(second.getContentAsString()).get("note").asText()).isEqualTo("a\nb");
        assertThat(edit("{\"base_revision\":3,\"representative_key_mode\":\"ORIGINAL\"}").getStatus()).isEqualTo(400);
        assertThat(edit("{\"base_revision\":3,\"representative_key_mode\":null}").getStatus()).isEqualTo(400);
        var cleared=edit("{\"base_revision\":3,\"note\":null,\"tier\":null,\"representative_key_mode\":null,\"representative_key_shift\":null}");assertThat(cleared.getStatus()).isEqualTo(200);
        var value=json.readTree(cleared.getContentAsString());assertThat(value.get("note").asText()).isEmpty();assertThat(value.get("tier").isNull()).isTrue();assertThat(value.get("representative_key_mode").isNull()).isTrue();assertThat(value.get("representative_key_shift").isNull()).isTrue();
        assertThat(edit("{\"base_revision\":4,\"representative_key_mode\":\"ORIGINAL\",\"representative_key_shift\":0}").getStatus()).isEqualTo(200);
    }
    @Test void replayUsesOriginalResponseAndStaleRevisionReturnsWireCurrent()throws Exception{
        String op=UUID.randomUUID().toString(),body="{\"base_revision\":1,\"title\":\"first\"}";
        var first=edit(op,body);assertThat(first.getStatus()).isEqualTo(200);
        assertThat(edit("{\"base_revision\":2,\"title\":\"later\"}").getStatus()).isEqualTo(200);
        assertThat(edit(op,body).getContentAsString()).isEqualTo(first.getContentAsString());
        assertThat(edit(op,body.replace("first","different")).getContentAsString()).contains("IDEMPOTENCY_CONFLICT");
        var conflict=edit(body);assertThat(conflict.getStatus()).isEqualTo(409);
        var error=json.readTree(conflict.getContentAsString()).get("error");assertThat(error.get("code").asText()).isEqualTo("REVISION_CONFLICT");
        assertThat(error.get("details").get("current_revision").asInt()).isEqualTo(3);assertThat(error.get("details").get("current").get("title").asText()).isEqualTo("later");
        assertThat(error.get("details").get("current").get("tier").isNull()).isTrue();assertThat(revision()).isEqualTo(3);assertThat(setup.count("change_log")).isEqualTo(3);
    }
    @Test void rejectsImmutableFieldsNullsOutOfRangeNumbersAndOversizedText()throws Exception{
        for(String entry:List.of("\"source_type\":\"MANUAL\"","\"tj_number\":\"123\"","\"language\":\"ko\"","\"user_id\":null","\"id\":null","\"source_token\":\"x\"","\"representative_recording_id\":null","\"title\":null","\"artist\":\"  \"","\"version_code\":null","\"tier\":\"X\"","\"representative_key_shift\":13","\"representative_key_shift\":-13","\"representative_key_shift\":1.5","\"representative_key_mode\":\"BAD\"","\"representative_key_mode\":\"ORIGINAL\",\"representative_key_shift\":1","\"representative_key_shift\":1"))
            assertThat(edit("{\"base_revision\":1,"+entry+"}").getStatus()).as(entry).isEqualTo(400);
        for(String body:List.of("{}","{\"base_revision\":0}","{\"base_revision\":9223372036854775808}","{\"base_revision\":1.1}","{\"base_revision\":\"1\"}"))assertThat(edit(body).getStatus()).isEqualTo(400);
        for(String field:List.of("title","artist","note"))assertThat(edit(json.writeValueAsString(Map.of("base_revision",1,field,"😀".repeat(field.equals("note")?2001:201)))).getStatus()).isEqualTo(400);
        assertThat(revision()).isEqualTo(1);assertThat(setup.count("mutation_receipt")).isEqualTo(1);
    }
    @Test void authenticationOwnershipAndLifecycleRemainEnforced()throws Exception{
        String body="{\"base_revision\":1,\"note\":\"secret\"}";
        assertThat(setup.mvc.perform(patch(path).contentType("application/json").content(body)).andReturn().getResponse().getStatus()).isEqualTo(401);
        var principal=setup.f.other.principal();var token=setup.f.sessions.issue(new AccountRegistrationService.Registration(principal.userId(),principal.deviceId(),false));
        var denied=editAs(path,UUID.randomUUID().toString(),body,token.accessToken(),principal.deviceId());assertThat(denied.getStatus()).isEqualTo(404);assertThat(denied.getContentAsString()).doesNotContain("원본 곡");
        for(String state:List.of("TRASHED","PURGE_PENDING","PURGED")){
            setup.f.jdbc.update("UPDATE song SET lifecycle_state=?",state);var response=edit(body);assertThat(response.getStatus()).isEqualTo(409);
            assertThat(response.getContentAsString()).contains(state.equals("TRASHED")?"SONG_RESTORE_REQUIRED":state.equals("PURGED")?"RESOURCE_PURGED":"SONG_PURGE_PENDING");
        }
        assertThat(revision()).isEqualTo(1);
    }
    @Test void queryKeyOrChangeLogFailureRollsBackAllWritesAndAllowsRetry()throws Exception{
        var oldKey=setup.f.jdbc.queryForObject("SELECT title_key FROM song_query_key",byte[].class);
        String op=UUID.randomUUID().toString(),body="{\"base_revision\":1,\"title\":\"changed\"}";
        for(String table:List.of("song_query_key","change_log")){
            if(table.equals("song_query_key"))setup.f.jdbc.execute("ALTER TABLE song_query_key ADD CONSTRAINT reject_edit CHECK(title_search<>X'6368616e676564')");
            else setup.f.jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT reject_edit CHECK(revision=1)");
            assertThat(edit(op,body).getStatus()).isEqualTo(500);assertThat(revision()).isEqualTo(1);
            assertThat(setup.f.jdbc.queryForObject("SELECT title FROM song",String.class)).isEqualTo("원본 곡");
            assertThat(setup.f.jdbc.queryForObject("SELECT title_key FROM song_query_key",byte[].class)).isEqualTo(oldKey);
            assertThat(setup.count("mutation_receipt")).isEqualTo(1);assertThat(setup.count("change_log")).isEqualTo(1);
            setup.f.jdbc.execute("ALTER TABLE "+table+" DROP CONSTRAINT reject_edit");
        }
        assertThat(edit(op,body).getStatus()).isEqualTo(200);
    }
    @Test void editInvalidatesListCursorAndEmptyPatchHasOneRevisionPerNewRequest()throws Exception{
        setup.id=UUID.randomUUID();assertThat(setup.postBody(UUID.randomUUID().toString(),setup.manual()).getStatus()).isEqualTo(201);
        String cursor=json.readTree(list("limit","1").getContentAsString()).get("next_cursor").asText();
        String op=UUID.randomUUID().toString(),body="{\"base_revision\":1}";
        assertThat(edit(op,body).getStatus()).isEqualTo(200);assertThat(edit(op,body).getStatus()).isEqualTo(200);assertThat(revision()).isEqualTo(2);
        var expired=list("limit","1","cursor",cursor);assertThat(expired.getStatus()).isEqualTo(409);assertThat(expired.getContentAsString()).contains("LIST_CURSOR_EXPIRED");
    }
}
