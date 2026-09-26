package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.config.SecurityConfig;
import com.ksh321.songrecord.api.web.GlobalExceptionHandler;
import java.time.LocalDateTime;
import java.util.UUID;
import org.junit.jupiter.api.*;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.mock.web.MockServletContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.support.AnnotationConfigWebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

class AuthHttpTests {
    AnnotationConfigWebApplicationContext context;
    MockMvc mvc;
    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({AuthHttpSecurityConfiguration.class,SecurityConfig.class,SocialAuthController.class,IdentityLinkController.class,GlobalExceptionHandler.class})
    static class Config {
        @Bean GoogleProofVerifier google(){return mock(GoogleProofVerifier.class);}
        @Bean KakaoProofVerifier kakao(){return mock(KakaoProofVerifier.class);}
        @Bean AccountRegistrationService accounts(){return mock(AccountRegistrationService.class);}
        @Bean IdentityLinkService links(){return mock(IdentityLinkService.class);}
        @Bean SessionService sessions(){return mock(SessionService.class);}
    }
    @BeforeEach void setup() {
        context=new AnnotationConfigWebApplicationContext();
        context.setServletContext(new MockServletContext());
        context.getEnvironment().setActiveProfiles("dev");context.register(Config.class);context.refresh();
        mvc=MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
    }
    @AfterEach void close(){context.close();}
    @Test void malformedJsonReturns400WithoutEchoingSecret() throws Exception {
        var response=mvc.perform(post("/v1/auth/social").contentType("application/json").content("{\"proof\":\"secret-proof"))
                .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(response.getContentAsString()).contains("VALIDATION_FAILED").doesNotContain("secret-proof");
    }
    @Test void unauthenticatedMeIs401AndOtherRoutesRemainDenied() throws Exception {
        assertThat(mvc.perform(get("/v1/auth/me")).andReturn().getResponse().getStatus()).isEqualTo(401);
        assertThat(mvc.perform(get("/private/account")).andReturn().getResponse().getStatus()).isEqualTo(403);
        assertThat(mvc.perform(get("/v1/auth/social")).andReturn().getResponse().getStatus()).isEqualTo(403);
    }
    @Test void postLoginWorksWithoutCsrfCookieAndReturnsNoStore() throws Exception {
        var user=UUID.randomUUID();var device=UUID.randomUUID();
        var identity=new VerifiedProviderIdentity("GOOGLE","verified");
        var account=new AccountRegistrationService.Registration(user,device,true);
        when(context.getBean(GoogleProofVerifier.class).verify("proof")).thenReturn(identity);
        when(context.getBean(AccountRegistrationService.class).register(identity,null,"Android")).thenReturn(account);
        when(context.getBean(SessionService.class).issue(account)).thenReturn(new SessionService.Tokens("access","refresh",
                LocalDateTime.of(2026,9,24,1,15),LocalDateTime.of(2026,10,24,1,0)));
        var result=mvc.perform(post("/v1/auth/social").contentType("application/json")
                .content("{\"provider\":\"GOOGLE\",\"proof\":\"proof\",\"deviceName\":\"Android\"}")).andReturn();
        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        assertThat(result.getResponse().getContentAsString()).contains(user.toString(),"2026-09-24T01:15:00Z");
        assertThat(result.getResponse().getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(result.getRequest().getSession(false)).isNull();
        assertThat(result.getResponse().getHeader("Set-Cookie")).isNull();
    }
    @Test void invalidProofIs401AndCreatesNoAccount() throws Exception {
        when(context.getBean(KakaoProofVerifier.class).verify("invalid")).thenThrow(ProofErrors.invalid());
        var response=mvc.perform(post("/v1/auth/social").contentType("application/json")
                .content("{\"provider\":\"KAKAO\",\"proof\":\"invalid\",\"deviceName\":\"Android\"}"))
                .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(401);
        verifyNoInteractions(context.getBean(AccountRegistrationService.class));
    }

    @Test void linkRoutesRequireBearerAndUnknownOperationsStayDenied() throws Exception {
        assertThat(mvc.perform(get("/v1/auth/identities")).andReturn().getResponse().getStatus()).isEqualTo(401);
        for(String route:java.util.List.of("reauth-challenges","link-challenges","link")) {
            var response=mvc.perform(post("/v1/auth/identities/"+route).contentType("application/json").content("{}"))
                    .andReturn().getResponse();
            assertThat(response.getStatus()).isEqualTo(401);
        }
        verifyNoInteractions(context.getBean(IdentityLinkService.class));
        assertThat(mvc.perform(post("/v1/auth/identities/anything")).andReturn().getResponse().getStatus()).isEqualTo(403);
    }
    @Test void linkResponseIsNoStoreAndHasNoSessionCookie() throws Exception {
        var device=UUID.randomUUID();var service=context.getBean(IdentityLinkService.class);
        when(service.begin("access",device,"GOOGLE","KAKAO")).thenReturn(new IdentityLinkService.Challenge("challenge","nonce","expiry"));
        var response=mvc.perform(post("/v1/auth/identities/reauth-challenges")
            .header("Authorization","Bearer access").header("X-Device-Id",device.toString())
            .contentType("application/json").content("{\"provider\":\"GOOGLE\",\"targetProvider\":\"KAKAO\"}"))
            .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(response.getHeader("Set-Cookie")).isNull();
    }

    @Test void unlinkRequiresBearerAndDispatchesWithNoStore() throws Exception {
        var id=UUID.randomUUID();var device=UUID.randomUUID();
        assertThat(mvc.perform(post("/v1/auth/identities/"+id+"/unlink")).andReturn().getResponse().getStatus()).isEqualTo(401);
        var response=mvc.perform(post("/v1/auth/identities/"+id+"/unlink")
                .header("Authorization","Bearer access").header("X-Device-Id",device.toString()))
                .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        verify(context.getBean(IdentityLinkService.class)).unlink("access",device,id);
    }
    @Test void logoutDispatchesRefreshProofWithoutCookie() throws Exception {
        var device=UUID.randomUUID();
        var response=mvc.perform(post("/v1/auth/logout").contentType("application/json")
                .content("{\"refreshToken\":\"synthetic\",\"deviceId\":\""+device+"\"}"))
                .andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(response.getContentAsString()).doesNotContain("synthetic");
        verify(context.getBean(SessionService.class)).logout("synthetic",device);
    }
}
