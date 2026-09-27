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
    @Import({SongConfiguration.class,SongController.class,SecurityConfig.class,GlobalExceptionHandler.class}) static class Config {}
    @BeforeEach void setup() throws Exception {
        f.setup();new ResourceDatabasePopulator(new ClassPathResource("revision-schema.sql"),new ClassPathResource("change-log-schema.sql")).populate(f.keeper);
        f.jdbc.execute("ALTER TABLE song ADD created_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP");
        f.jdbc.execute("ALTER TABLE song ADD reserved_tj_number VARCHAR(20) GENERATED ALWAYS AS (CASE WHEN lifecycle_state='PURGED' THEN NULL ELSE tj_number END)");
        f.jdbc.execute("CREATE UNIQUE INDEX test_song_number ON song(user_id,reserved_tj_number)");
        f.jdbc.execute("CREATE TABLE song_source(song_id BINARY(16) PRIMARY KEY,user_id BINARY(16),provider VARCHAR(16) CHECK(provider='TJ'),source_title VARCHAR(200),source_artist VARCHAR(200),source_ref VARCHAR(255),verified_at TIMESTAMP(3),created_at TIMESTAMP(3),FOREIGN KEY(song_id) REFERENCES song(id))");
        f.jdbc.execute("CREATE TABLE deletion_ledger(user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),object_generation BINARY(16),revision BIGINT)");
        context=new AnnotationConfigWebApplicationContext();context.setServletContext(new MockServletContext());context.getEnvironment().setActiveProfiles("dev");
        context.addBeanFactoryPostProcessor(b->{
            b.registerSingleton("jdbc",f.jdbc);b.registerSingleton("access",f.access);b.registerSingleton("mutations",f.mutations);
            b.registerSingleton("guard",new CreationGuard(f.jdbc,f.access,f.manager));b.registerSingleton("changes",new AccountChanges(f.jdbc,f.access,f.manager,f.clock));
            b.registerSingleton("candidates",new TjCandidates(token->{
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
        assertThat(mvc.perform(get("/v1/songs")).andReturn().getResponse().getStatus()).isEqualTo(403);
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
}
