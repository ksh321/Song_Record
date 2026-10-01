package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.config.SecurityConfig;
import com.ksh321.songrecord.api.web.*;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.context.annotation.*;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

class ChangeHttpTests {
    AnnotationConfigWebApplicationContext context;MockMvc mvc;AccountAccess access;ChangeReadView view;
    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({ChangeHttpSecurityConfiguration.class,ChangeController.class,SecurityConfig.class,GlobalExceptionHandler.class})
    static class Config {
        @Bean AccountAccess access(){return mock(AccountAccess.class);}
        @Bean ChangeReadView view(){return mock(ChangeReadView.class);}
        @Bean ChangeQueries queries(AccountAccess access,ChangeReadView view){return new ChangeQueries(access,view);}
    }
    @BeforeEach void setup(){
        context=new AnnotationConfigWebApplicationContext();context.setServletContext(new MockServletContext());
        context.getEnvironment().setActiveProfiles("dev");context.register(Config.class);context.refresh();
        mvc=MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        access=context.getBean(AccountAccess.class);view=context.getBean(ChangeReadView.class);
    }
    @AfterEach void close(){context.close();}
    @Test void authenticatesBeforeReadingEvenWhenQueryIsMalformed()throws Exception{
        when(access.authenticate(null,null)).thenThrow(new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","Authentication required",false,Map.of()));
        assertThat(mvc.perform(get("/v1/sync/changes").param("after_seq","bad")).andReturn().getResponse().getStatus()).isEqualTo(401);
        verifyNoInteractions(view);
    }
    @Test void rejectsUnknownDuplicateMissingOverflowAndInvalidLimits()throws Exception{
        when(access.authenticate(null,null)).thenReturn(mock(AccountAccess.Account.class));
        for(String value:new String[]{"-1","01","1.0","9223372036854775808","", "1e2"})
            assertThat(mvc.perform(get("/v1/sync/changes").param("after_seq",value)).andReturn().getResponse().getStatus()).isEqualTo(400);
        for(String value:new String[]{"0","101","-1","01"})
            assertThat(mvc.perform(get("/v1/sync/changes").param("after_seq","0").param("limit",value)).andReturn().getResponse().getStatus()).isEqualTo(400);
        assertThat(mvc.perform(get("/v1/sync/changes")).andReturn().getResponse().getStatus()).isEqualTo(400);
        assertThat(mvc.perform(get("/v1/sync/changes").param("after_seq","0","1")).andReturn().getResponse().getStatus()).isEqualTo(400);
        assertThat(mvc.perform(get("/v1/sync/changes").param("after_seq","0").param("user_id",UUID.randomUUID().toString())).andReturn().getResponse().getStatus()).isEqualTo(400);
        verifyNoInteractions(view);
    }
    @Test void allowedGetForwardsAuthorityAndReturnsOnlyValidatedCursorWithoutSession()throws Exception{
        var account=mock(AccountAccess.Account.class);when(access.authenticate("Bearer fixture","fixture-device")).thenReturn(account);
        var change=new AccountChanges.Change(AccountChanges.Entity.RECORDING,UUID.randomUUID(),9,AccountChanges.Operation.DELETE,"{\"deleted\":true}");
        var entry=new ChangeWindow.Entry(4,change,Instant.parse("2030-01-01T00:00:00Z"));
        when(view.read(account,3,50)).thenReturn(new ChangeWindow.Page(3,4,4,false,List.of(entry)));
        var result=mvc.perform(get("/v1/sync/changes").header("Authorization","Bearer fixture").header("X-Device-Id","fixture-device").param("after_seq","3")).andReturn();
        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        var body=new JsonMapper().readTree(result.getResponse().getContentAsString());
        assertThat(body.get("next_seq").asLong()).isEqualTo(4);assertThat(body.get("has_more").asBoolean()).isFalse();
        assertThat(body.get("changes").get(0).get("operation").asText()).isEqualTo("DELETE");
        assertThat(body.get("changes").get(0).get("payload").get("deleted").asBoolean()).isTrue();
        assertThat(result.getResponse().getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(result.getResponse().getHeader("Set-Cookie")).isNull();assertThat(result.getRequest().getSession(false)).isNull();
        verify(view).read(account,3,50);
    }
    @Test void expiredCursorRemainsAnExplicitRestartError()throws Exception{
        var account=mock(AccountAccess.Account.class);when(access.authenticate(null,null)).thenReturn(account);
        when(view.read(account,0,50)).thenThrow(ChangeWindow.expired());
        var response=mvc.perform(get("/v1/sync/changes").param("after_seq","0")).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(409);assertThat(response.getContentAsString()).contains("CURSOR_EXPIRED");
    }
    @Test void revocationBeforeReplyPreventsReturningPreparedPayload()throws Exception{
        var account=mock(AccountAccess.Account.class);when(access.authenticate(null,null)).thenReturn(account);
        when(view.read(account,0,50)).thenReturn(new ChangeWindow.Page(0,0,0,false,List.of()));
        when(access.revalidate(account)).thenThrow(new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","Authentication required",false,Map.of()));
        var response=mvc.perform(get("/v1/sync/changes").param("after_seq","0")).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(401);assertThat(response.getContentAsString()).doesNotContain("next_seq");
    }
    @Test void otherMethodsAndNestedRoutesStayDenied()throws Exception{
        for(var request:List.of(post("/v1/sync/changes"),delete("/v1/sync/changes"),head("/v1/sync/changes"),get("/v1/sync/changes/other")))
            assertThat(mvc.perform(request).andReturn().getResponse().getStatus()).isEqualTo(403);
        verifyNoInteractions(access,view);
    }
}
