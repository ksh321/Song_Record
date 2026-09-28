package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.songs.*;
import com.ksh321.songrecord.api.pagination.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

class SongListingTests {
    final SongCreationTests setup=new SongCreationTests();
    @BeforeEach void open() throws Exception {
        setup.setup();
        for(String column:List.of("origin_device_id BINARY(16)","timezone_id VARCHAR(64)","timezone_offset_minutes INT"))setup.f.jdbc.execute("ALTER TABLE recording ADD "+column);
    }
    @AfterEach void close()throws Exception{setup.close();}
    MockHttpServletResponse getList(String... params)throws Exception{
        var request=get("/v1/songs").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId());
        for(int i=0;i<params.length;i+=2)request.param(params[i],params[i+1]);return setup.mvc.perform(request).andReturn().getResponse();
    }
    void create()throws Exception{assertThat(setup.postBody(UUID.randomUUID().toString(),setup.manual()).getStatus()).isEqualTo(201);setup.id=UUID.randomUUID();}
    @Test void actualSqlAllSortsViewsRecentRecordingAndSearchMatchSharedExpectations()throws Exception{
        var f=setup.f;var pages=setup.context.getBean(KeysetPages.class);
        SongListingDatabaseChecks.verify(f.jdbc,pages,f.account,f.registration.userId(),f.registration.deviceId());
    }
    @Test void endpointReturnsCountVersionDatesAndCursorAndRejectsChangedQuery()throws Exception{
        create();create();var first=getList("limit","1");assertThat(first.getStatus()).isEqualTo(200);assertThat(first.getHeader("Cache-Control")).isEqualTo("no-store");
        var json=new JsonMapper().readTree(first.getContentAsString());assertThat(json.get("count").asLong()).isEqualTo(2);assertThat(json.get("items").size()).isEqualTo(1);
        var song=json.get("items").get(0);assertThat(song.get("version_code").asText()).isEqualTo("NORMAL");assertThat(song.get("created_at").asText()).endsWith("Z");assertThat(song.get("latest_recorded_at").isNull()).isTrue();
        String cursor=json.get("next_cursor").asText();var last=getList("limit","1","cursor",cursor);assertThat(last.getStatus()).isEqualTo(200);
        assertThat(new JsonMapper().readTree(last.getContentAsString()).get("next_cursor").isNull()).isTrue();
        for(String[] changed:List.of(new String[]{"limit","2"},new String[]{"limit","1","sort","TITLE"},new String[]{"limit","1","view","TIER_GROUPED"},new String[]{"limit","1","q","x"})){
            var params=new ArrayList<>(List.of(changed));params.add("cursor");params.add(cursor);
            assertThat(getList(params.toArray(String[]::new)).getContentAsString()).contains("INVALID_CURSOR");
        }
        create();assertThat(getList("limit","1","cursor",cursor).getStatus()).isEqualTo(409);
    }
    @Test void authenticationAndAccountBoundaryCannotBeReplacedByQueryParameters()throws Exception{
        create();assertThat(setup.mvc.perform(get("/v1/songs")).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(getList("user_id",setup.f.other.principal().userId().toString()).getStatus()).isEqualTo(400);
        var other=setup.f.other.principal();var token=setup.f.sessions.issue(new AccountRegistrationService.Registration(other.userId(),other.deviceId(),false));
        var response=setup.mvc.perform(get("/v1/songs").header("Authorization","Bearer "+token.accessToken()).header("X-Device-Id",other.deviceId())).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(200);assertThat(new JsonMapper().readTree(response.getContentAsString()).get("count").asInt()).isZero();
    }
    @Test void malformedAndRepeatedParametersAre400AndMissingIndexIs503()throws Exception{
        for(String[] params:List.of(new String[]{"limit","x"},new String[]{"limit","0"},new String[]{"limit","101"},new String[]{"sort","TITLE DESC"},new String[]{"cursor",""},new String[]{"q","a","q","b"},new String[]{"view","bad"}))assertThat(getList(params).getStatus()).isEqualTo(400);
        create();setup.f.jdbc.update("DELETE FROM song_query_key");assertThat(getList().getStatus()).isEqualTo(503);assertThat(getList().getContentAsString()).contains("SONG_INDEX_NOT_READY");
    }
    @Test void keyInsertFailureRollsBackSongReceiptAndChangeLog()throws Exception{
        setup.f.jdbc.execute("ALTER TABLE song_query_key ADD CONSTRAINT reject_key CHECK(key_version='bad')");
        assertThat(setup.postBody(setup.f.key,setup.manual()).getStatus()).isEqualTo(500);
        for(String table:List.of("song","song_query_key","mutation_receipt","change_log"))assertThat(setup.count(table)).isZero();
    }
    @Test void backfillHandlesMultipleBatchesWithoutChangingUserValuesOrRevision()throws Exception{
        UUID owner=setup.f.registration.userId();
        for(int i=0;i<251;i++)SongListingDatabaseChecks.add(setup.f.jdbc,owner,new UUID(0,i+1),"노래"+i,"가수","ACTIVE");
        setup.f.jdbc.update("DELETE FROM song_query_key");
        db.migration.V11__backfill_song_query_keys.backfill(setup.f.jdbc);
        assertThat(setup.count("song_query_key")).isEqualTo(251);
        assertThat(setup.f.jdbc.queryForObject("SELECT SUM(revision) FROM song",Long.class)).isEqualTo(251);
        assertThat(setup.f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,bytes(owner))).isZero();
        var list=getList("limit","100","sort","TITLE");assertThat(list.getStatus()).isEqualTo(200);assertThat(new JsonMapper().readTree(list.getContentAsString()).get("count").asInt()).isEqualTo(251);
    }
}
