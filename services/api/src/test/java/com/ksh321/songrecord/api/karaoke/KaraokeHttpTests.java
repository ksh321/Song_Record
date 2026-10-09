package com.ksh321.songrecord.api.karaoke;
import com.ksh321.songrecord.api.auth.*;
import com.ksh321.songrecord.api.config.SecurityConfig;
import com.ksh321.songrecord.api.songs.*;
import com.ksh321.songrecord.api.web.GlobalExceptionHandler;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
class KaraokeHttpTests {
    AnnotationConfigWebApplicationContext context;MockMvc mvc;UUID owner=UUID.randomUUID(),other=UUID.randomUUID(),device=UUID.randomUUID(),active=UUID.randomUUID();
    @Configuration @EnableWebMvc @EnableWebSecurity @Import({KaraokeConfiguration.class,KaraokeController.class,SecurityConfig.class,GlobalExceptionHandler.class})
    static class Config {
        @Bean SessionService sessions(){return mock(SessionService.class);}
        @Bean AccountAccess access(SessionService sessions){return new AccountAccess(sessions);}
        @Bean JdbcTemplate jdbc(){var jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";DB_CLOSE_DELAY=-1","sa",""));jdbc.execute("CREATE TABLE song(id BINARY(16),user_id BINARY(16),source_type VARCHAR(20),lifecycle_state VARCHAR(20),tj_number VARCHAR(20))");return jdbc;}
        @Bean @Primary SourceTokens testSource(){return new SourceTokens(new byte[32],Clock.systemUTC());}
        @Bean @Primary KaraokeSearch testSearch(AccountAccess access,SearchLimit limit){return new KaraokeSearch(access,limit,(b,k,q)->q.equals("empty")?List.of():List.of(new MananaSearchAdapter.Candidate(b,"00123","원본 (LIVE)","가수","MANANA","manana:"+(b==CandidateVerifier.Brand.TJ?"tj":"kumyoung")+":00123")));}
    }
    @BeforeEach void setup(){context=new AnnotationConfigWebApplicationContext();context.setServletContext(new MockServletContext());context.getEnvironment().setActiveProfiles("dev");context.register(Config.class);context.refresh();mvc=MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();when(context.getBean(SessionService.class).authenticate("fixture",device)).thenReturn(new SessionService.Principal(owner,device,UUID.randomUUID()));var jdbc=context.getBean(JdbcTemplate.class);jdbc.update("INSERT INTO song VALUES(?,?,?,?,?)",SongQueryKeys.bytes(active),SongQueryKeys.bytes(owner),"TJ","ACTIVE","00123");jdbc.update("INSERT INTO song VALUES(?,?,?,?,?)",SongQueryKeys.bytes(UUID.randomUUID()),SongQueryKeys.bytes(other),"TJ","ACTIVE","00123");jdbc.update("INSERT INTO song VALUES(?,?,?,?,?)",SongQueryKeys.bytes(UUID.randomUUID()),SongQueryKeys.bytes(owner),"TJ","DELETED","00123");}
    @AfterEach void close(){context.close();}
    @Test void endpointAuthenticatesScopesMatchesPreservesOriginalsAndNeverCaches()throws Exception {
        assertThat(mvc.perform(get("/v1/karaoke/search").param("brand","TJ").param("q","곡")).andReturn().getResponse().getStatus()).isEqualTo(401);
        var tj=mvc.perform(get("/v1/karaoke/search").header("Authorization","Bearer fixture").header("X-Device-Id",device.toString()).param("brand","TJ").param("q","곡")).andReturn().getResponse();assertThat(tj.getStatus()).isEqualTo(200);assertThat(tj.getHeader("Cache-Control")).isEqualTo("no-store");var json=new JsonMapper();var row=json.readTree(tj.getContentAsString()).get("results").get(0);assertThat(row.get("matched_song_id").asString()).isEqualTo(active.toString());assertThat(row.get("number").asString()).isEqualTo("00123");assertThat(row.get("title").asString()).isEqualTo("원본 (LIVE)");assertThat(row.get("source_token").asString()).startsWith("s1.");
        var ky=mvc.perform(get("/v1/karaoke/search").header("Authorization","Bearer fixture").header("X-Device-Id",device.toString()).param("brand","KY").param("q","곡")).andReturn().getResponse();assertThat(json.readTree(ky.getContentAsString()).get("results").get(0).get("matched_song_id").isNull()).isTrue();
        var empty=mvc.perform(get("/v1/karaoke/search").header("Authorization","Bearer fixture").header("X-Device-Id",device.toString()).param("brand","TJ").param("q","empty")).andReturn().getResponse();assertThat(json.readTree(empty.getContentAsString()).get("results").isEmpty()).isTrue();
        var invalid=mvc.perform(get("/v1/karaoke/search").header("Authorization","Bearer fixture").header("X-Device-Id",device.toString()).param("brand","TJ","KY").param("q","曲")).andReturn().getResponse();assertThat(invalid.getStatus()).isEqualTo(400);assertThat(invalid.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(mvc.perform(post("/v1/karaoke/search")).andReturn().getResponse().getStatus()).isEqualTo(403);
    }
}
