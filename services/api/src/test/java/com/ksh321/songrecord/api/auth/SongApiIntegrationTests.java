package com.ksh321.songrecord.api.auth;

import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

/** Server HTTP integration; mobile pending-reference remapping remains P10-04. */
class SongApiIntegrationTests {
    final SongCreationTests setup=new SongCreationTests();final JsonMapper json=new JsonMapper();
    record Client(String token,UUID device){}
    Client a,aSecond,b;
    @BeforeEach void open()throws Exception{
        setup.setup();new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(setup.f.keeper);a=new Client(setup.f.tokens.accessToken(),setup.f.registration.deviceId());
        var registrations=new AccountRegistrationService(setup.f.jdbc,setup.f.manager,setup.f.clock);
        var second=registrations.register(new VerifiedProviderIdentity("GOOGLE","a"),null,"second phone");
        assertThat(second.userId()).isEqualTo(setup.f.registration.userId());assertThat(second.deviceId()).isNotEqualTo(a.device);
        aSecond=new Client(setup.f.sessions.issue(second).accessToken(),second.deviceId());
        var p=setup.f.other.principal();b=new Client(setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false)).accessToken(),p.deviceId());
    }
    @AfterEach void close()throws Exception{setup.close();}
    MockHttpServletResponse send(Client c,MockHttpServletRequestBuilder request,String op,String body)throws Exception{
        request.header("Authorization","Bearer "+c.token).header("X-Device-Id",c.device);
        if(op!=null)request.header("Idempotency-Key",op);if(body!=null)request.contentType("application/json").content(body);
        return setup.mvc.perform(request).andReturn().getResponse();
    }
    JsonNode ok(MockHttpServletResponse response,int status)throws Exception{assertThat(response.getStatus()).as(response.getContentAsString()).isEqualTo(status);return json.readTree(response.getContentAsString());}
    JsonNode create(Client c,UUID id,String proof,String artist,String version,String key)throws Exception{
        return ok(send(c,post("/v1/songs"),key,json.writeValueAsString(Map.of("id",id.toString(),"source_type","TJ","source_token",proof,"title","공통 제목","artist",artist,"version_code",version))),201);
    }
    @Test void twoDevicesConvergeThenEditSelectAndReadOneCanonicalSong()throws Exception{
        UUID song=UUID.randomUUID(),pending=UUID.randomUUID();create(a,song,"valid","개인 가수","LIVE",UUID.randomUUID().toString());
        String duplicate=json.writeValueAsString(Map.of("id",pending.toString(),"source_type","TJ","source_token","valid","title","덮어쓰기 금지","artist","다른 표기","version_code","MR"));
        String op=UUID.randomUUID().toString();var response=send(aSecond,post("/v1/songs"),op,duplicate);var mapped=ok(response,200);
        assertThat(mapped.get("canonical_song_id").asText()).isEqualTo(song.toString());assertThat(mapped.get("created").asBoolean()).isFalse();
        assertThat(mapped.get("song").get("artist").asText()).isEqualTo("개인 가수");assertThat(mapped.get("song").get("version_code").asText()).isEqualTo("LIVE");
        assertThat(setup.f.jdbc.queryForObject("SELECT COUNT(*) FROM song WHERE id=?",Integer.class,bytes(pending))).isZero();
        var edited=ok(send(aSecond,patch("/v1/songs/"+song),UUID.randomUUID().toString(),"{\"base_revision\":1,\"title\":\"통합 검색 제목\",\"note\":\"입력 유지\"}"),200);
        assertThat(edited.get("revision").asInt()).isEqualTo(2);
        UUID recording=UUID.randomUUID();setup.f.jdbc.update("INSERT INTO recording(id,user_id,song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,metadata_state,lifecycle_state,recorded_at) VALUES(?,?,?,'과거 제목','과거 가수','NORMAL','ORIGINAL',0,'SAVED','ACTIVE',CURRENT_TIMESTAMP)",bytes(recording),bytes(setup.f.registration.userId()),bytes(song));
        ok(send(a,put("/v1/songs/"+song+"/representative"),UUID.randomUUID().toString(),"{\"base_revision\":2,\"recording_id\":\""+recording+"\"}"),200);
        var listed=ok(send(aSecond,get("/v1/songs").param("q","통합 검색"),null,null),200);
        assertThat(listed.get("count").asInt()).isEqualTo(1);var item=listed.get("items").get(0);assertThat(item.get("id").asText()).isEqualTo(song.toString());assertThat(item.get("representative_recording_id").asText()).isEqualTo(recording.toString());assertThat(item.get("revision").asInt()).isEqualTo(3);
        // The original response is immutable even after later editing and selection.
        assertThat(send(aSecond,post("/v1/songs"),op,duplicate).getContentAsString()).isEqualTo(response.getContentAsString());
        assertThat(setup.count("change_log")).isEqualTo(3);assertThat(setup.f.jdbc.queryForObject("SELECT title_snapshot FROM recording",String.class)).isEqualTo("과거 제목");
        assertThat(ok(send(a,patch("/v1/songs/"+song),UUID.randomUUID().toString(),"{\"base_revision\":1,\"title\":\"stale\"}"),409).get("error").get("code").asText()).isEqualTo("REVISION_CONFLICT");
    }
    @Test void sameNumberAndOperationKeyAreAccountScopedAndSearchExcludesForeignAndTrash()throws Exception{
        UUID aSong=UUID.randomUUID(),bSong=UUID.randomUUID(),differentNumber=UUID.randomUUID();String shared=UUID.randomUUID().toString();
        create(a,aSong,"valid","공통 가수","NORMAL",shared);create(b,bSong,"valid","공통 가수","NORMAL",shared);
        create(a,differentNumber,"second","공통 가수","NORMAL",UUID.randomUUID().toString());
        var aList=ok(send(a,get("/v1/songs").param("q","공통 제목"),null,null),200);assertThat(aList.get("count").asInt()).isEqualTo(2);
        var bList=ok(send(b,get("/v1/songs").param("q","공통 제목"),null,null),200);assertThat(bList.get("count").asInt()).isEqualTo(1);assertThat(bList.toString()).contains(bSong.toString()).doesNotContain(aSong.toString(),differentNumber.toString());
        for(var request:List.of(patch("/v1/songs/"+aSong),put("/v1/songs/"+aSong+"/representative"))){
            String body=request.buildRequest(new org.springframework.mock.web.MockServletContext()).getMethod().equals("PATCH")?"{\"base_revision\":1,\"note\":\"attack\"}":"{\"base_revision\":1,\"recording_id\":null}";
            assertThat(ok(send(b,request,UUID.randomUUID().toString(),body),404).get("error").get("code").asText()).isEqualTo("RESOURCE_NOT_FOUND");
        }
        setup.f.jdbc.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(aSong));
        assertThat(ok(send(a,get("/v1/songs").param("q","공통 제목"),null,null),200).get("count").asInt()).isEqualTo(1);
        assertThat(ok(send(b,get("/v1/songs").param("q","공통 제목"),null,null),200).get("count").asInt()).isEqualTo(1);
        assertThat(setup.count("song")).isEqualTo(3);assertThat(setup.count("song_source")).isEqualTo(3);
    }
}
