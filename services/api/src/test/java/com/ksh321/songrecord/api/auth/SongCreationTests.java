package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.songs.*;
import com.ksh321.songrecord.api.revision.CreationGuard;
import com.ksh321.songrecord.api.sync.AccountChanges;
import com.ksh321.songrecord.api.config.SecurityConfig;
import com.ksh321.songrecord.api.web.GlobalExceptionHandler;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.context.annotation.*;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

class SongCreationTests {
    final IdempotencyTests f=new IdempotencyTests();AnnotationConfigWebApplicationContext context;MockMvc mvc;UUID id=UUID.randomUUID();
    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({com.ksh321.songrecord.api.playlists.PlaylistConfiguration.class,com.ksh321.songrecord.api.playlists.PlaylistController.class,com.ksh321.songrecord.api.classifications.ConditionConfiguration.class,com.ksh321.songrecord.api.classifications.ConditionController.class,com.ksh321.songrecord.api.classifications.TagConfiguration.class,com.ksh321.songrecord.api.classifications.TagController.class,com.ksh321.songrecord.api.recordings.RecordingConfiguration.class,com.ksh321.songrecord.api.recordings.RecordingController.class,SongConfiguration.class,SongController.class,SecurityConfig.class,GlobalExceptionHandler.class}) static class Config {}
    @BeforeEach void setup() throws Exception {
        f.setup();new ResourceDatabasePopulator(new ClassPathResource("revision-schema.sql"),new ClassPathResource("change-log-schema.sql")).populate(f.keeper);
        f.jdbc.execute("ALTER TABLE playlist ADD created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
        f.jdbc.execute("CREATE TABLE playlist_item(id BINARY(16) PRIMARY KEY,user_id BINARY(16),playlist_id BINARY(16),song_id BINARY(16),candidate_brand VARCHAR(2),candidate_number VARCHAR(20),candidate_snapshot VARCHAR(4000),entry_key VARCHAR(64),position BIGINT,hidden_by_batch_id BINARY(16),created_at TIMESTAMP(3),updated_at TIMESTAMP(3),UNIQUE(playlist_id,entry_key))");
        f.jdbc.execute("ALTER TABLE song ADD created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
        f.jdbc.execute("ALTER TABLE song ADD reserved_tj_number VARCHAR(20) GENERATED ALWAYS AS (CASE WHEN lifecycle_state='PURGED' THEN NULL ELSE tj_number END)");
        f.jdbc.execute("CREATE UNIQUE INDEX test_song_number ON song(user_id,reserved_tj_number)");
        f.jdbc.execute("CREATE TABLE song_source(song_id BINARY(16) PRIMARY KEY,user_id BINARY(16),provider VARCHAR(16) CHECK(provider='TJ'),source_title VARCHAR(200),source_artist VARCHAR(200),source_ref VARCHAR(255),verified_at TIMESTAMP(3),created_at TIMESTAMP(3),FOREIGN KEY(song_id) REFERENCES song(id))");
        f.jdbc.execute("CREATE TABLE deletion_ledger(user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),object_generation BINARY(16),revision BIGINT)");
        new ResourceDatabasePopulator(new ClassPathResource("song-query-schema.sql")).populate(f.keeper);
        f.jdbc.execute("ALTER TABLE recording ADD recorded_at TIMESTAMP(3)");
        context=new AnnotationConfigWebApplicationContext();context.setServletContext(new MockServletContext());context.getEnvironment().setActiveProfiles("dev");
        context.addBeanFactoryPostProcessor(b->{
            b.registerSingleton("revisions",new com.ksh321.songrecord.api.revision.RevisionChanges(f.jdbc,f.access,f.manager,f.clock));
            b.registerSingleton("pages",new com.ksh321.songrecord.api.pagination.KeysetPages(f.jdbc,f.access,f.manager,new com.ksh321.songrecord.api.pagination.PageCursor(new byte[32],f.clock,Duration.ofMinutes(30))));
            b.registerSingleton("jobs",new com.ksh321.songrecord.api.jobs.JobQueue(f.jdbc,f.access,f.manager,f.clock,Duration.ofMinutes(2),5));
            b.registerSingleton("jdbc",f.jdbc);b.registerSingleton("access",f.access);b.registerSingleton("mutations",f.mutations);
            b.registerSingleton("guard",new CreationGuard(f.jdbc,f.access,f.manager));b.registerSingleton("changes",new AccountChanges(f.jdbc,f.access,f.manager,f.clock));
            b.registerSingleton("candidates",new TjCandidates(token->{
                if(token.equals("outage"))throw new com.ksh321.songrecord.api.web.ApiException(org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE,"CANDIDATE_VERIFICATION_UNAVAILABLE","unavailable",true,Map.of());
                if(!Set.of("valid","second","ky").contains(token))throw new com.ksh321.songrecord.api.web.ApiException(org.springframework.http.HttpStatus.BAD_REQUEST,"SOURCE_TOKEN_INVALID","invalid",false,Map.of());
                return new CandidateVerifier.Verified("FIXTURE",token.equals("ky")?CandidateVerifier.Brand.KY:CandidateVerifier.Brand.TJ,token.equals("second")?"990002":"990001","원본 곡","원본 가수",f.clock.instant,f.clock.instant.plusSeconds(86400));
            },f.clock));
        });context.register(Config.class);context.refresh();mvc=MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }
    @AfterEach void close() throws Exception {if(context!=null)context.close();f.close();}
    String body(String extra){return "{\"id\":\""+id+"\",\"source_type\":\"TJ\",\"source_token\":\"valid\""+extra+"}";}
    org.springframework.mock.web.MockHttpServletResponse postBody(String key,String body) throws Exception {var result=mvc.perform(post("/v1/songs").header("Authorization","Bearer "+f.tokens.accessToken()).header("X-Device-Id",f.registration.deviceId()).header("Idempotency-Key",key).contentType("application/json").content(body)).andReturn();return result.getResponse();}
    int count(String table){return f.jdbc.queryForObject("SELECT COUNT(*) FROM "+table,Integer.class);}
    @Test void creates201WithDefaultsAndOneAtomicChange(){
        try {var r=postBody(f.key,body(""));assertThat(r.getStatus()).isEqualTo(201);assertThat(r.getHeader("Cache-Control")).isEqualTo("no-store");assertThat(r.getContentAsString()).contains("\"created\":true","\"version_code\":\"NORMAL\"","\"revision\":1");}
        catch(Exception e){throw new RuntimeException(e);}
        for(String t:List.of("song","song_source","change_log","mutation_receipt"))assertThat(count(t)).isEqualTo(1);
    }
    @Test void editableValuesDoNotOverwriteSourceOriginals() throws Exception {
        assertThat(postBody(f.key,body(",\"title\":\" 내 제목 \",\"artist\":\"내 가수\",\"version_code\":\"LIVE\",\"note\":\"메모\",\"tier\":\"A\"")).getStatus()).isEqualTo(201);
        assertThat(f.jdbc.queryForObject("SELECT title FROM song",String.class)).isEqualTo("내 제목");assertThat(f.jdbc.queryForObject("SELECT source_title FROM song_source",String.class)).isEqualTo("원본 곡");
    }
    @Test void replayAndChangedBodyConflict() throws Exception {
        var first=postBody(f.key,body(""));assertThat(postBody(f.key,body("")).getContentAsString()).isEqualTo(first.getContentAsString());
        assertThat(postBody(f.key,body(",\"note\":\"different\"")).getStatus()).isEqualTo(409);assertThat(count("change_log")).isEqualTo(1);
    }
    @Test void unauthorizedAndUnimplementedRoutesRemainBlocked() throws Exception {
        assertThat(mvc.perform(post("/v1/songs").contentType("application/json").content(body(""))).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(mvc.perform(get("/v1/songs")).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(mvc.perform(post("/v1/songs/other")).andReturn().getResponse().getStatus()).isEqualTo(403);assertThat(count("song")).isZero();
    }
    @Test void forgedFieldsNullsAndUnknownValuesAreRejected() throws Exception {
        for(String extra:List.of(",\"tj_number\":\"1\"",",\"user_id\":\"other\"",",\"title\":null",",\"version_code\":\"BAD\"",",\"tier\":\"X\"",",\"title\":\"   \""))assertThat(postBody(UUID.randomUUID().toString(),body(extra)).getStatus()).isEqualTo(400);
        assertThat(postBody(f.key,body("").replace("valid","ky")).getStatus()).isEqualTo(400);assertThat(count("song")).isZero();assertThat(count("mutation_receipt")).isZero();
    }
    @Test void sourceFailureRollsBackSongReceiptAndChangeSequence() throws Exception {
        f.jdbc.execute("ALTER TABLE song_source ADD CONSTRAINT injected CHECK(provider<>'TJ')");
        assertThat(postBody(f.key,body("")).getStatus()).isEqualTo(500);
        for(String t:List.of("song","song_source","change_log","mutation_receipt"))assertThat(count(t)).isZero();
        assertThat(f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,OwnershipTests.bytes(f.registration.userId()))).isZero();
    }
    @Test void sameNumberUsesExistingCanonicalWithoutOverwriting() throws Exception {
        postBody(f.key,body(",\"note\":\"keep\""));UUID first=id;id=UUID.randomUUID();
        var response=postBody(UUID.randomUUID().toString(),body(",\"note\":\"replace\""));assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getContentAsString()).contains(first.toString(),"keep");assertThat(count("song")).isEqualTo(1);assertThat(count("change_log")).isEqualTo(1);
    }
    @Test void deletedUuidAndTrashCannotBeRecreated() throws Exception {
        f.jdbc.update("INSERT INTO deletion_ledger VALUES(?,'SONG',?,NULL,2)",OwnershipTests.bytes(f.registration.userId()),OwnershipTests.bytes(id));
        assertThat(postBody(f.key,body("")).getContentAsString()).contains("RESOURCE_PURGED");
        id=UUID.randomUUID();postBody(f.key,body(""));f.jdbc.update("UPDATE song SET lifecycle_state='TRASHED'");
        assertThat(postBody(UUID.randomUUID().toString(),body("")).getContentAsString()).contains("SONG_RESTORE_REQUIRED");
    }
    @Test void canonicalMappingPreservesAllExistingEditsAndDoesNotAdvanceSequence() throws Exception {
        postBody(f.key,body(",\"note\":\"keep\",\"version_code\":\"LIVE\",\"tier\":\"S\""));
        UUID canonical=id;
        f.jdbc.update("UPDATE song SET representative_key_mode='MALE',representative_key_shift=3,revision=8 WHERE id=?",OwnershipTests.bytes(canonical));
        var before=f.jdbc.queryForMap("SELECT title,artist,note,version_code,song_tier,representative_key_mode,representative_key_shift,revision,updated_at FROM song WHERE id=?",OwnershipTests.bytes(canonical));
        id=UUID.randomUUID();var response=postBody(UUID.randomUUID().toString(),body(",\"note\":\"replace\",\"version_code\":\"MR\",\"tier\":\"D\""));
        assertThat(response.getStatus()).isEqualTo(200);
        var json=new tools.jackson.databind.json.JsonMapper().readTree(response.getContentAsString());
        assertThat(json.get("canonical_song_id").asText()).isEqualTo(canonical.toString());
        assertThat(json.get("song").get("revision").asLong()).isEqualTo(8);
        assertThat(f.jdbc.queryForMap("SELECT title,artist,note,version_code,song_tier,representative_key_mode,representative_key_shift,revision,updated_at FROM song WHERE id=?",OwnershipTests.bytes(canonical))).isEqualTo(before);
        assertThat(count("change_log")).isEqualTo(1);assertThat(count("song_source")).isEqualTo(1);
        assertThat(f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,OwnershipTests.bytes(f.registration.userId()))).isEqualTo(1);
    }
    @Test void reservedNumberStatesAndPurgedUuidTakePriority() throws Exception {
        postBody(f.key,body(""));UUID canonical=id;id=UUID.randomUUID();
        for(String state:List.of("TRASHED","PURGE_PENDING")) {
            f.jdbc.update("UPDATE song SET lifecycle_state=? WHERE id=?",state,OwnershipTests.bytes(canonical));
            var response=postBody(UUID.randomUUID().toString(),body(""));assertThat(response.getStatus()).isEqualTo(409);
            assertThat(response.getContentAsString()).contains(state.equals("TRASHED")?"SONG_RESTORE_REQUIRED":"SONG_PURGE_PENDING");
        }
        f.jdbc.update("UPDATE song SET lifecycle_state='PURGED' WHERE id=?",OwnershipTests.bytes(canonical));
        f.jdbc.update("INSERT INTO deletion_ledger VALUES(?,'SONG',?,NULL,2)",OwnershipTests.bytes(f.registration.userId()),OwnershipTests.bytes(canonical));
        UUID replacement=id;assertThat(postBody(UUID.randomUUID().toString(),body("")).getStatus()).isEqualTo(201);
        id=canonical;assertThat(postBody(UUID.randomUUID().toString(),body("")).getContentAsString()).contains("RESOURCE_PURGED");
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song WHERE id=?",Integer.class,OwnershipTests.bytes(replacement))).isEqualTo(1);
    }
    @Test void sameUuidCannotSwitchToDifferentNumber() throws Exception {
        postBody(f.key,body(""));var response=postBody(UUID.randomUUID().toString(),body("").replace("valid","second"));
        assertThat(response.getStatus()).isEqualTo(409);assertThat(response.getContentAsString()).contains("SONG_ID_CONFLICT");
        assertThat(f.jdbc.queryForObject("SELECT tj_number FROM song",String.class)).isEqualTo("990001");
    }
    @Test void sameTitleDifferentNumbersRemainTwoSongs() throws Exception {
        postBody(f.key,body(""));id=UUID.randomUUID();assertThat(postBody(UUID.randomUUID().toString(),body("").replace("valid","second")).getStatus()).isEqualTo(201);
        assertThat(count("song")).isEqualTo(2);assertThat(count("change_log")).isEqualTo(2);
    }
    @Test void sameNumberInOtherAccountNeverMapsAcrossOwners() throws Exception {
        postBody(f.key,body(""));UUID otherId=UUID.randomUUID();
        var tokens=f.sessions.issue(new AccountRegistrationService.Registration(f.other.principal().userId(),f.other.principal().deviceId(),false));
        var response=mvc.perform(post("/v1/songs").header("Authorization","Bearer "+tokens.accessToken()).header("X-Device-Id",f.other.principal().deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(body("").replace(id.toString(),otherId.toString()))).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(201);assertThat(response.getContentAsString()).contains(otherId.toString()).doesNotContain(id.toString());assertThat(count("song")).isEqualTo(2);
    }


    String manual(){return "{\"id\":\""+id+"\",\"source_type\":\"MANUAL\",\"manual_reason\":\"TJ_NOT_FOUND\",\"title\":\" 수동 곡 \",\"artist\":\" 가수 \"}";}
    @Test void manualCreatesWithoutNumberOrSourceAndReplaysAtomically() throws Exception {
        var first=postBody(f.key,manual());assertThat(first.getStatus()).isEqualTo(201);
        assertThat(first.getContentAsString()).contains("\"tj_number\":null","\"source_type\":\"MANUAL\"","\"title\":\"수동 곡\"");
        assertThat(postBody(f.key,manual()).getContentAsString()).isEqualTo(first.getContentAsString());
        assertThat(postBody(f.key,manual().replace("수동 곡","변경")).getStatus()).isEqualTo(409);
        for(String table:List.of("song","change_log","mutation_receipt"))assertThat(count(table)).isEqualTo(1);
        assertThat(count("song_source")).isZero();
        assertThat(f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,OwnershipTests.bytes(f.registration.userId()))).isEqualTo(1);
    }
    @Test void manualSameTitleUsesUuidAndExistingUuidDoesNotOverwrite() throws Exception {
        postBody(f.key,manual());UUID first=id;
        var duplicate=postBody(UUID.randomUUID().toString(),manual().replace("수동 곡","새 제목"));
        assertThat(duplicate.getStatus()).isEqualTo(200);assertThat(duplicate.getContentAsString()).contains(first.toString(),"수동 곡").doesNotContain("새 제목");
        id=UUID.randomUUID();assertThat(postBody(UUID.randomUUID().toString(),manual()).getStatus()).isEqualTo(201);
        assertThat(count("song")).isEqualTo(2);assertThat(count("change_log")).isEqualTo(2);assertThat(count("song_source")).isZero();
    }
    @Test void manualRejectsMissingReasonNamesAndDirectNumbers() throws Exception {
        String valid=manual();
        for(String invalid:List.of(valid.replace(",\"manual_reason\":\"TJ_NOT_FOUND\"",""),valid.replace("TJ_NOT_FOUND","SEARCH_FAILED"),valid.replace("\" 수동 곡 \"","null"),valid.replace("\" 가수 \"","\"  \""),valid.replace(",\"title\":\" 수동 곡 \"",""),valid.replace(",\"artist\":\" 가수 \"",""),valid.replace("수동 곡","가".repeat(201)),valid.replace("가수","가".repeat(201)))) {
            assertThat(postBody(UUID.randomUUID().toString(),invalid).getStatus()).isEqualTo(400);
        }
        for(String field:List.of("\"tj_number\":\"123\"","\"tj_number\":null","\"source_token\":\"valid\"","\"source_token\":null","\"user_id\":\"other\"")) {
            assertThat(postBody(UUID.randomUUID().toString(),valid.substring(0,valid.length()-1)+","+field+"}").getStatus()).isEqualTo(400);
        }
        assertThat(postBody(UUID.randomUUID().toString(),body(",\"manual_reason\":\"TJ_NOT_FOUND\"")).getStatus()).isEqualTo(400);
        assertThat(count("song")).isZero();assertThat(count("mutation_receipt")).isZero();
    }
    @Test void searchOutageNeverCreatesManualFallback() throws Exception {
        var failed=postBody(f.key,body("").replace("valid","outage"));assertThat(failed.getStatus()).isEqualTo(503);
        for(String table:List.of("song","song_source","change_log","mutation_receipt"))assertThat(count(table)).isZero();
        // Previously confirmed manual input needs no provider access.
        assertThat(postBody(UUID.randomUUID().toString(),manual()).getStatus()).isEqualTo(201);
    }
    @Test void manualCannotChangeSourceTypeOrBypassLifecycle() throws Exception {
        postBody(f.key,manual());
        assertThat(postBody(UUID.randomUUID().toString(),body("")).getContentAsString()).contains("SONG_ID_CONFLICT");
        for(String state:List.of("TRASHED","PURGE_PENDING")){
            f.jdbc.update("UPDATE song SET lifecycle_state=?",state);
            assertThat(postBody(UUID.randomUUID().toString(),manual()).getContentAsString()).contains(state.equals("TRASHED")?"SONG_RESTORE_REQUIRED":"SONG_PURGE_PENDING");
        }
        f.jdbc.update("INSERT INTO deletion_ledger VALUES(?,'SONG',?,NULL,2)",OwnershipTests.bytes(f.registration.userId()),OwnershipTests.bytes(id));
        assertThat(postBody(UUID.randomUUID().toString(),manual()).getContentAsString()).contains("RESOURCE_PURGED");
        assertThat(count("song")).isEqualTo(1);
    }
    @Test void manualChangeLogFailureRollsBackReceiptAndSong() throws Exception {
        f.jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT reject_manual CHECK(entity_type<>'SONG')");
        assertThat(postBody(f.key,manual()).getStatus()).isEqualTo(500);
        for(String table:List.of("song","change_log","mutation_receipt"))assertThat(count(table)).isZero();
        assertThat(f.jdbc.queryForObject("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",Long.class,OwnershipTests.bytes(f.registration.userId()))).isZero();
    }

}
