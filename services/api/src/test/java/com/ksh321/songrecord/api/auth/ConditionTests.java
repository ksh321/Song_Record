package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.classifications.*;
import com.ksh321.songrecord.api.recordings.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.mock.web.MockHttpServletResponse;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

class ConditionTests {
    final RecordingEditingTests setup=new RecordingEditingTests();
    @BeforeEach void open()throws Exception{setup.open();}
    @AfterEach void close()throws Exception{setup.close();}
    MockHttpServletResponse create(UUID id,String name)throws Exception{return setup.setup.setup.mvc.perform(post("/v1/conditions").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId()).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(setup.json.writeValueAsString(Map.of("id",id.toString(),"name",name)))).andReturn().getResponse();}
    MockHttpServletResponse list(String... pairs)throws Exception{var r=get("/v1/conditions").header("Authorization","Bearer "+setup.f.tokens.accessToken()).header("X-Device-Id",setup.f.registration.deviceId());for(int i=0;i<pairs.length;i+=2)r.param(pairs[i],pairs[i+1]);return setup.setup.setup.mvc.perform(r).andReturn().getResponse();}
    @Test void mysqlSharedDefinitionHistorySelectionRollbackAndRace(){var c=setup.setup.setup.context;ConditionDatabaseChecks.verify(setup.f.jdbc,c.getBean(ConditionService.class),c.getBean(RecordingDrafts.class),c.getBean(RecordingEditing.class),"Bearer "+setup.f.tokens.accessToken(),setup.f.registration.deviceId().toString(),setup.f.registration.userId());}
    @Test void uuidConditionAppearsInRecordingFiltersAndExpiresCursor()throws Exception{
        UUID custom=UUID.randomUUID();assertThat(create(custom,"피곤함").getStatus()).isEqualTo(201);String cursor=setup.json.readTree(list("limit","1").getContentAsString()).get("next_cursor").asText();
        setup.setup.create(setup.setup.base());assertThat(setup.edit(Map.of("base_revision",1,"condition_code",custom.toString())).getStatus()).isEqualTo(200);
        var recordings=setup.json.readTree(setup.listing.list("condition_code",custom.toString()).getContentAsString());assertThat(recordings.get("count").asInt()).isEqualTo(1);assertThat(recordings.get("items").get(0).get("condition_code").asText()).isEqualTo(custom.toString());
        assertThat(setup.json.readTree(setup.listing.list("condition_code","NONE").getContentAsString()).get("count").asInt()).isZero();
        assertThat(list("limit","1","cursor",cursor).getContentAsString()).contains("LIST_CURSOR_EXPIRED");
    }
    @Test void defaultsAreAccountScopedAndForeignCustomSelectionIsRejected()throws Exception{
        var service=setup.setup.setup.context.getBean(ConditionService.class);UUID custom=UUID.randomUUID();create(custom,"private");
        var p=setup.f.other.principal();var tokens=setup.f.sessions.issue(new AccountRegistrationService.Registration(p.userId(),p.deviceId(),false));String auth="Bearer "+tokens.accessToken();
        var other=service.list(auth,p.deviceId().toString(),new org.springframework.util.LinkedMultiValueMap<>());assertThat(other.count()).isEqualTo(4);
        assertThatThrownBy(()->service.rename(auth,p.deviceId().toString(),UUID.randomUUID().toString(),custom.toString(),"{\"base_revision\":1,\"name\":\"other\"}")).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.status().value()).isEqualTo(404));
        UUID foreign=UUID.randomUUID();service.create(auth,p.deviceId().toString(),UUID.randomUUID().toString(),setup.json.writeValueAsString(Map.of("id",foreign.toString(),"name","foreign")));
        setup.setup.create(setup.setup.base());assertThat(setup.edit(Map.of("base_revision",1,"condition_code",foreign.toString())).getStatus()).isEqualTo(404);
        assertThat(setup.edit(Map.of("base_revision",1,"condition_code","GOOD")).getStatus()).isEqualTo(200);
        assertThat(setup.setup.setup.mvc.perform(get("/v1/conditions")).andReturn().getResponse().getStatus()).isEqualTo(401);
    }
    @Test void crudValidationNormalizationAndRevision()throws Exception{
        UUID id=UUID.randomUUID();assertThat(create(id,"  HELLO  ").getStatus()).isEqualTo(201);assertThat(create(UUID.randomUUID(),"hello").getContentAsString()).contains("CONDITION_NAME_IN_USE");assertThat(create(UUID.randomUUID()," ").getStatus()).isEqualTo(400);assertThat(create(UUID.randomUUID(),"😀".repeat(51)).getStatus()).isEqualTo(400);
        var service=setup.setup.setup.context.getBean(ConditionService.class);String auth="Bearer "+setup.f.tokens.accessToken(),device=setup.f.registration.deviceId().toString();
        assertThat(service.rename(auth,device,UUID.randomUUID().toString(),id.toString(),"{\"base_revision\":1,\"name\":\"changed\"}").status()).isEqualTo(200);
        assertThatThrownBy(()->service.rename(auth,device,UUID.randomUUID().toString(),id.toString(),"{\"base_revision\":1,\"name\":\"stale\"}")).isInstanceOfSatisfying(com.ksh321.songrecord.api.web.ApiException.class,e->assertThat(e.code()).isEqualTo("REVISION_CONFLICT"));
        var response=setup.setup.setup.mvc.perform(post("/v1/conditions/"+id+"/archive").header("Authorization",auth).header("X-Device-Id",device).header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content("{\"base_revision\":2}")).andReturn().getResponse();assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");assertThat(setup.json.readTree(response.getContentAsString()).get("code").asText()).isEqualTo(id.toString());
        assertThat(create(id,"retry").getContentAsString()).contains("CONDITION_ARCHIVED");assertThat(list("state","BAD").getStatus()).isEqualTo(400);
    }
}
