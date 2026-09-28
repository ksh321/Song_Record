package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.recordings.*;
import db.migration.V13__backfill_recording_query_keys;
import com.ksh321.songrecord.api.pagination.*;
import java.util.*;
import org.junit.jupiter.api.*;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

class RecordingListingTests {
    final RecordingDraftTests setup=new RecordingDraftTests();
    @BeforeEach void open()throws Exception{
        setup.open();var db=setup.setup.f.jdbc;
        db.execute("ALTER TABLE tag ADD normalized_name_key VARBINARY(800)");
        db.execute("CREATE TABLE recording_file_spec(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),sha256 CHAR(64),size_bytes BIGINT,duration_ms INT,codec VARCHAR(32),sample_rate INT,channels SMALLINT,capture_integrity VARCHAR(32))");
        db.execute("CREATE TABLE recording_asset(recording_id BINARY(16) PRIMARY KEY,user_id BINARY(16),cloud_state VARCHAR(16),blocked_reason VARCHAR(32),object_key VARCHAR(512),generation BINARY(16),verified_size BIGINT,sha256 CHAR(64),stored_at TIMESTAMP(3))");
        db.execute("CREATE TABLE recording_tag(user_id BINARY(16),recording_id BINARY(16),tag_id BINARY(16),name_snapshot VARCHAR(50),PRIMARY KEY(recording_id,tag_id))");
        db.execute("CREATE TABLE song_cloud_selection(song_id BINARY(16) PRIMARY KEY,user_id BINARY(16),representative_id BINARY(16),latest_id BINARY(16),lowest_tier_id BINARY(16))");
        db.execute("CREATE TABLE pin_slot(user_id BINARY(16),slot_no INT,current_recording_id BINARY(16),pending_recording_id BINARY(16))");
    }
    @AfterEach void close()throws Exception{setup.close();}
    @Test void sqlFiltersAndEverySortMatchRulesAcrossAllPages(){RecordingListingDatabaseChecks.verify(setup.setup.f.jdbc,setup.setup.context.getBean(KeysetPages.class),setup.setup.f.account,setup.setup.f.registration.userId(),setup.setup.f.registration.deviceId());}
    org.springframework.mock.web.MockHttpServletResponse list(String... pairs)throws Exception{
        var r=get("/v1/recordings").header("Authorization","Bearer "+setup.setup.f.tokens.accessToken()).header("X-Device-Id",setup.setup.f.registration.deviceId());for(int i=0;i<pairs.length;i+=2)r.param(pairs[i],pairs[i+1]);return setup.setup.mvc.perform(r).andReturn().getResponse();
    }
    @Test void httpNoFilesCountCursorMutationAndOwnerIsolation()throws Exception{
        var json=new JsonMapper();for(int i=0;i<3;i++){setup.id=UUID.randomUUID();assertThat(setup.create(setup.base()).getStatus()).isEqualTo(201);}
        var first=list("limit","1");assertThat(first.getStatus()).isEqualTo(200);assertThat(first.getHeader("Cache-Control")).isEqualTo("no-store");var page=json.readTree(first.getContentAsString());assertThat(page.get("count").asInt()).isEqualTo(3);assertThat(page.get("items").get(0).get("cloud").get("stored").asBoolean()).isFalse();String cursor=page.get("next_cursor").asText();
        assertThat(list("limit","1","cursor",cursor).getStatus()).isEqualTo(200);assertThat(list("limit","1","cursor",cursor,"server_file","PRESENT").getStatus()).isEqualTo(400);
        var p=setup.setup.f.other.principal();var token=setup.setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));var request=get("/v1/recordings").header("Authorization","Bearer "+token.accessToken()).header("X-Device-Id",p.deviceId());assertThat(json.readTree(setup.setup.mvc.perform(request).andReturn().getResponse().getContentAsString()).get("count").asInt()).isZero();
        setup.id=UUID.randomUUID();setup.create(setup.base());assertThat(list("limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
        assertThat(setup.setup.mvc.perform(get("/v1/recordings")).andReturn().getResponse().getStatus()).isEqualTo(401);assertThat(list("local_file","PRESENT").getStatus()).isEqualTo(400);
    }
    @Test void backfillCoversMultipleBatchesAndNullTitlesWithoutChangingMetadata()throws Exception{
        var db=setup.setup.f.jdbc;for(int i=0;i<251;i++){var id=new UUID(0,1000+i);db.update("INSERT INTO recording(id,user_id,title_snapshot,metadata_state,lifecycle_state) VALUES(?,?,?,'DRAFT','ACTIVE')",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(id),com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(setup.setup.f.registration.userId()),i==250?null:"곡"+i);}
        var before=db.queryForList("SELECT id,title_snapshot,revision FROM recording ORDER BY id");V13__backfill_recording_query_keys.backfill(db);assertThat(setup.setup.count("recording_query_key")).isEqualTo(251);V13__backfill_recording_query_keys.backfill(db);assertThat(db.queryForList("SELECT id,title_snapshot,revision FROM recording ORDER BY id")).usingRecursiveComparison().isEqualTo(before);
    }
    @Test void savedTransitionReplacesTitleKeyAtomicallyAndExpiresCursor()throws Exception{
        var json=new JsonMapper();var body=setup.base();body.put("title_snapshot","zzz");assertThat(setup.create(body).getStatus()).isEqualTo(201);UUID target=setup.id;
        setup.id=UUID.randomUUID();body=setup.base();body.put("title_snapshot","middle");assertThat(setup.create(body).getStatus()).isEqualTo(201);
        String cursor=json.readTree(list("sort","TITLE","limit","1").getContentAsString()).get("next_cursor").asText();
        var file=Map.of("size_bytes",10,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        String save=json.writeValueAsString(Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","alpha","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file));String key=UUID.randomUUID().toString();var db=setup.setup.f.jdbc;
        byte[] before=db.queryForObject("SELECT title_key FROM recording_query_key WHERE recording_id=?",byte[].class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(target));
        db.execute("ALTER TABLE change_log ADD CONSTRAINT reject_listing_save CHECK(revision=1)");
        var saving=setup.setup.context.getBean(RecordingSaving.class);
        assertThatThrownBy(()->saving.save("Bearer "+setup.setup.f.tokens.accessToken(),setup.setup.f.registration.deviceId().toString(),key,target.toString(),save)).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(db.queryForObject("SELECT title_key FROM recording_query_key WHERE recording_id=?",byte[].class,com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(target))).isEqualTo(before);
        db.execute("ALTER TABLE change_log DROP CONSTRAINT reject_listing_save");assertThat(saving.save("Bearer "+setup.setup.f.tokens.accessToken(),setup.setup.f.registration.deviceId().toString(),key,target.toString(),save).status()).isEqualTo(200);
        assertThat(json.readTree(list("sort","TITLE").getContentAsString()).get("items").get(0).get("id").asText()).isEqualTo(target.toString());assertThat(list("sort","TITLE","limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
    }

}
