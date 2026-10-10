package com.ksh321.songrecord.api.charts;
import com.ksh321.songrecord.api.auth.*;import com.ksh321.songrecord.api.config.SecurityConfig;import com.ksh321.songrecord.api.karaoke.SourceTokens;import com.ksh321.songrecord.api.web.*;
import java.time.*;import java.nio.charset.StandardCharsets;import java.util.*;
import org.junit.jupiter.api.*;import org.springframework.context.annotation.*;import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.transaction.PlatformTransactionManager;import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;import org.springframework.mock.web.MockServletContext;import org.springframework.test.web.servlet.*;import org.springframework.test.web.servlet.setup.MockMvcBuilders;import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;import org.springframework.web.servlet.config.annotation.EnableWebMvc;import tools.jackson.databind.json.JsonMapper;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import static org.assertj.core.api.Assertions.*;import static org.mockito.Mockito.*;import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
class ChartHttpTests {
    AnnotationConfigWebApplicationContext context;MockMvc mvc;UUID device=UUID.randomUUID();
    @Configuration @EnableWebMvc @EnableWebSecurity @Import({ChartQueryConfiguration.class,ChartController.class,SecurityConfig.class,GlobalExceptionHandler.class}) static class Config {
        @Bean(destroyMethod="close") ChartDatabaseFixture fixture()throws Exception{return new ChartDatabaseFixture();}
        @Bean JdbcTemplate jdbc(ChartDatabaseFixture f){return f.jdbc;}@Bean PlatformTransactionManager manager(ChartDatabaseFixture f){return f.manager;}
        @Bean SessionService sessions(){return mock(SessionService.class);}@Bean AccountAccess access(SessionService s){return new AccountAccess(s);}@Bean SourceTokens tokens(){return new SourceTokens(new byte[32],Clock.systemUTC());}
    }
    @BeforeEach void setup(){context=new AnnotationConfigWebApplicationContext();context.setServletContext(new MockServletContext());context.getEnvironment().setActiveProfiles("dev");context.register(Config.class);context.refresh();mvc=MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();when(context.getBean(SessionService.class).authenticate("fixture",device)).thenReturn(new SessionService.Principal(UUID.randomUUID(),device,UUID.randomUUID()));for(String brand:List.of("TJ","KY")){var scope=ChartScope.parse(brand,"MONTHLY");var f=context.getBean(ChartDatabaseFixture.class);var p=new ChartPublication(f.jdbc,f.manager,f.validation,Clock.systemUTC());var ticket=p.begin(scope);var id=f.staging.stage(scope,("[{\"brand\":\""+scope.providerBrand()+"\",\"no\":\"00123\",\"title\":\"원본 (LIVE)\",\"singer\":\"가수\"}]").getBytes(StandardCharsets.UTF_8),Instant.parse("2026-10-01T00:00:00Z"));p.publish(scope,ticket,id);}}
    @AfterEach void close(){context.close();}
    MockHttpServletRequestBuilder request(String brand,String period){return get("/v1/charts/popular").header("Authorization","Bearer fixture").header("X-Device-Id",device.toString()).param("brand",brand).param("period",period);}
    @Test void authenticationValidationSourceProofAndKyPolicyAreEnforced()throws Exception{
        assertThat(mvc.perform(get("/v1/charts/popular").param("brand","TJ").param("period","MONTHLY")).andReturn().getResponse().getStatus()).isEqualTo(401);
        var response=mvc.perform(request("TJ","MONTHLY")).andReturn().getResponse();assertThat(response.getStatus()).isEqualTo(200);assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");var root=new JsonMapper().readTree(response.getContentAsString());assertThat(root.get("stale").asBoolean()).isFalse();var item=root.get("items").get(0);assertThat(item.get("number").asString()).isEqualTo("00123");assertThat(item.get("title").asString()).isEqualTo("원본 (LIVE)");var proof=context.getBean(SourceTokens.class).read(item.get("source_token").asString());assertThat(proof.candidate().number()).isEqualTo("00123");assertThat(proof.expiresAt()).isEqualTo(proof.issuedAt().plus(Duration.ofHours(24)));
        var ky=new JsonMapper().readTree(mvc.perform(request("KY","MONTHLY")).andReturn().getResponse().getContentAsString());assertThat(ky.get("items").get(0).get("source_token").isNull()).isTrue();assertThat(ky.has("matched_song_id")).isFalse();
        for(var invalid:List.of(request("TJ","MONTHLY").param("brand","KY"),request("TJ","MONTHLY").param("year_month","2026-01"),request("tj","MONTHLY"),request("TJ","YEARLY"))){var bad=mvc.perform(invalid).andReturn().getResponse();assertThat(bad.getStatus()).isEqualTo(400);assertThat(bad.getContentAsString()).contains("VALIDATION_FAILED");}
        assertThat(mvc.perform(post("/v1/charts/popular")).andReturn().getResponse().getStatus()).isEqualTo(403);assertThat(mvc.perform(request("TJ","DAILY")).andReturn().getResponse().getStatus()).isEqualTo(503);
    }
    @Test void revokedSessionDuringReadCannotReturnSourceTokens()throws Exception{var session=context.getBean(SessionService.class);when(session.authenticate("fixture",device)).thenReturn(new SessionService.Principal(UUID.randomUUID(),device,UUID.randomUUID()));assertThat(mvc.perform(request("TJ","MONTHLY")).andReturn().getResponse().getStatus()).isEqualTo(200);var principal=new SessionService.Principal(UUID.randomUUID(),device,UUID.randomUUID());when(session.authenticate("fixture",device)).thenReturn(principal,principal).thenThrow(new ApiException(org.springframework.http.HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","다시 로그인",false,Map.of()));assertThat(mvc.perform(request("TJ","MONTHLY")).andReturn().getResponse().getStatus()).isEqualTo(401);}
    byte[] acceptancePayload(ChartScope scope) {
        String row="{\"brand\":\""+scope.providerBrand()+"\",\"no\":\"00123\",\"title\":\"검수 원본 (LIVE)\",\"singer\":\"검수 가수\"}";
        return ("["+row+","+row.replace("00123","00999")+"]").getBytes(StandardCharsets.UTF_8);
    }
    ChartCollection acceptanceWorker(ChartDatabaseFixture f, ChartCollection.Source source) {
        var clock=Clock.fixed(Instant.parse("2026-10-10T00:00:00Z"),ZoneOffset.UTC);
        var publication=new ChartPublication(f.jdbc,f.manager,f.validation,clock);
        return new ChartCollection(source,f.staging::stage,clock,true,new ChartCollection.Lifecycle(){
            public UUID begin(ChartScope scope){return publication.begin(scope);}
            public void success(ChartScope scope,UUID attempt,UUID id){assertThat(publication.publish(scope,attempt,id)).isTrue();}
        });
    }
    @Test void sixScopeCollectionPublicationAndHttpRetainExactOldDataForEveryFailure() throws Exception {
        var f=context.getBean(ChartDatabaseFixture.class);
        var scopes=new ArrayList<ChartScope>();
        for(var brand:com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.values())for(var period:ChartScope.Period.values())scopes.add(new ChartScope(brand,period));
        var normal=acceptanceWorker(f,(scope,remaining)->acceptancePayload(scope));
        for(var scope:scopes)normal.run(scope);
        var query=new ChartQuery(f.jdbc,f.manager);var mapper=new JsonMapper();
        for(var scope:scopes){
            var before=query.read(scope);assertThat(before.stale()).isFalse();
            var normalHttp=mvc.perform(request(scope.brand().name(),scope.period().name())).andReturn().getResponse();
            assertThat(normalHttp.getStatus()).isEqualTo(200);assertThat(normalHttp.getHeader("Cache-Control")).isEqualTo("no-store");
            var wire=mapper.readTree(normalHttp.getContentAsString());
            assertThat(wire.get("brand").asString()).isEqualTo(scope.brand().name());
            assertThat(wire.get("period").asString()).isEqualTo(scope.period().name());
            assertThat(wire.get("source_url").asString()).isEqualTo(scope.sourceUri().toString());
            assertThat(wire.get("fetched_at").asString()).isEqualTo("2026-10-10T00:00:00Z");
            assertThat(wire.has("year_month")||wire.has("is_final")||wire.has("source_updated_at")).isFalse();
            assertThat(wire.get("items").size()).isEqualTo(2);
            for(int n=0;n<2;n++){
                var row=wire.get("items").get(n);assertThat(row.get("position").asInt()).isEqualTo(n+1);
                assertThat(row.get("number").asString()).isEqualTo(n==0?"00123":"00999");
                if(scope.brand()==com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.TJ){
                    var proof=context.getBean(SourceTokens.class).read(row.get("source_token").asString());
                    assertThat(proof.candidate().brand()).isEqualTo(scope.brand());
                    assertThat(proof.candidate().number()).isEqualTo(row.get("number").asString());
                    assertThat(proof.candidate().title()).isEqualTo("검수 원본 (LIVE)");
                }else assertThat(row.get("source_token").isNull()).isTrue();
            }
            String good=new String(acceptancePayload(scope),StandardCharsets.UTF_8);
            String wrong=good.replace(scope.providerBrand(),scope.providerBrand().equals("tj")?"kumyoung":"tj");
            String duplicate=good.replace("00999","00123");
            for(String bad:List.of("[]","[{}]",wrong,duplicate,good.substring(0,good.length()-1))){
                var failure=acceptanceWorker(f,(s,remaining)->bad.getBytes(StandardCharsets.UTF_8));
                assertThatThrownBy(()->failure.run(scope)).isInstanceOf(ChartValidation.InvalidChart.class);
                var after=query.read(scope);assertThat(after.stale()).isTrue();assertThat(after.scope()).isEqualTo(scope);
                assertThat(after.revision()).isEqualTo(before.revision());assertThat(after.fetchedAt()).isEqualTo(before.fetchedAt());assertThat(after.items()).isEqualTo(before.items());
                var response=mvc.perform(request(scope.brand().name(),scope.period().name())).andReturn().getResponse();assertThat(response.getStatus()).isEqualTo(200);
                var stale=mapper.readTree(response.getContentAsString());assertThat(stale.get("stale").asBoolean()).isTrue();
                assertThat(stale.get("source_url").asString()).isEqualTo(scope.sourceUri().toString());
                assertThat(stale.get("revision").asLong()).isEqualTo(before.revision());assertThat(stale.get("fetched_at").asString()).isEqualTo(wire.get("fetched_at").asString());
                assertThat(stale.get("items").get(0).get("number").asString()).isEqualTo("00123");
            }
            for(var failure:List.of(ChartCollection.Failure.NETWORK,ChartCollection.Failure.TIMEOUT)){
                var calls=new java.util.concurrent.atomic.AtomicInteger();
                var broken=acceptanceWorker(f,(s,remaining)->{calls.incrementAndGet();throw new ChartCollection.CollectionFailure(failure);});
                assertThatThrownBy(()->broken.run(scope)).isInstanceOfSatisfying(ChartCollection.CollectionFailure.class,e->assertThat(e.kind()).isEqualTo(failure));
                assertThat(calls).hasValue(2);assertThat(query.read(scope).items()).isEqualTo(before.items());
                assertThat(query.read(scope).revision()).isEqualTo(before.revision());assertThat(query.read(scope).stale()).isTrue();
            }
            // Identical content across periods and refreshes is valid; never invent a difference.
            normal.run(scope);var refreshed=query.read(scope);assertThat(refreshed.items()).isEqualTo(before.items());
            assertThat(refreshed.stale()).isFalse();assertThat(refreshed.revision()).isGreaterThan(before.revision());
        }
    }
    @Test void failedFirstCollectionForEachScopeHasNoOtherPeriodFallback() throws Exception {
        for(var brand:com.ksh321.songrecord.api.songs.CandidateVerifier.Brand.values())for(var period:ChartScope.Period.values()){
            try(var f=new ChartDatabaseFixture()){
                var scope=new ChartScope(brand,period);var other=new ChartScope(brand,period==ChartScope.Period.DAILY?ChartScope.Period.MONTHLY:ChartScope.Period.DAILY);
                acceptanceWorker(f,(s,remaining)->acceptancePayload(s)).run(other);
                var empty=acceptanceWorker(f,(s,remaining)->"[]".getBytes(StandardCharsets.UTF_8));
                assertThatThrownBy(()->empty.run(scope)).isInstanceOf(ChartValidation.InvalidChart.class);
                var query=new ChartQuery(f.jdbc,f.manager);
                assertThatThrownBy(()->query.read(scope)).isInstanceOfSatisfying(ApiException.class,e->assertThat(e.code()).isEqualTo("CHART_SOURCE_UNAVAILABLE"));
                assertThat(query.read(other).stale()).isFalse();
            }
        }
    }

}
