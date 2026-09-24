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
    @Import({AuthHttpSecurityConfiguration.class,SecurityConfig.class,SocialAuthController.class,GlobalExceptionHandler.class})
    static class Config {
        @Bean GoogleProofVerifier google(){return mock(GoogleProofVerifier.class);}
        @Bean KakaoProofVerifier kakao(){return mock(KakaoProofVerifier.class);}
        @Bean AccountRegistrationService accounts(){return mock(AccountRegistrationService.class);}
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
}
