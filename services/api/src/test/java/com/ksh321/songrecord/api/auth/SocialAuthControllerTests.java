package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.LocalDateTime;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class SocialAuthControllerTests {
    GoogleProofVerifier google=mock(GoogleProofVerifier.class);
    KakaoProofVerifier kakao=mock(KakaoProofVerifier.class);
    AccountRegistrationService accounts=mock(AccountRegistrationService.class);
    SessionService sessions=mock(SessionService.class);
    DefaultListableBeanFactory beans=new DefaultListableBeanFactory();
    UUID user=UUID.randomUUID(), device=UUID.randomUUID();
    SessionService.Tokens tokens=new SessionService.Tokens("access-secret","refresh-secret",
            LocalDateTime.of(2026,9,24,1,15),LocalDateTime.of(2026,10,24,1,0));
    SocialAuthController controller;
    @BeforeEach void setup() {
        beans.registerSingleton("google",google);beans.registerSingleton("kakao",kakao);
        controller=new SocialAuthController(beans.getBeanProvider(GoogleProofVerifier.class),
                beans.getBeanProvider(KakaoProofVerifier.class),accounts,sessions);
    }
    @Test void googleIssuesOnlyForVerifiedIdentityAndUsesServerDevice() {
        var identity=new VerifiedProviderIdentity("GOOGLE","verified-id");
        var account=new AccountRegistrationService.Registration(user,device,true);
        when(google.verify("proof")).thenReturn(identity);
        when(accounts.register(identity,null,"Android")).thenReturn(account);
        when(sessions.issue(account)).thenReturn(tokens);
        var response=controller.login(new SocialAuthController.LoginRequest("GOOGLE","proof","Android"));
        assertThat(response.getHeaders().getCacheControl()).isEqualTo("no-store");
        assertThat(response.getBody().userId()).isEqualTo(user.toString());
        assertThat(response.getBody().deviceId()).isEqualTo(device.toString());
        assertThat(response.getBody().accessExpiresAt()).isEqualTo("2026-09-24T01:15:00Z");
        verifyNoInteractions(kakao);
    }
    @Test void kakaoSelectsKakaoVerifier() {
        var identity=new VerifiedProviderIdentity("KAKAO","123");
        var account=new AccountRegistrationService.Registration(user,device,false);
        when(kakao.verify("proof")).thenReturn(identity);
        when(accounts.register(identity,null,"Android")).thenReturn(account);
        when(sessions.issue(account)).thenReturn(tokens);
        assertThat(controller.login(new SocialAuthController.LoginRequest("KAKAO","proof","Android")).getBody().userId()).isEqualTo(user.toString());
        verifyNoInteractions(google);
    }
    @Test void failedProofCannotRegisterOrIssueTokens() {
        when(google.verify(anyString())).thenThrow(ProofErrors.invalid());
        assertThatThrownBy(()->controller.login(new SocialAuthController.LoginRequest("GOOGLE","fake","Android")))
                .isInstanceOf(ApiException.class);
        verifyNoInteractions(accounts,sessions);
    }
    @Test void absentProviderIsUnavailable() {
        beans.destroySingleton("google");
        assertThatThrownBy(()->controller.login(new SocialAuthController.LoginRequest("GOOGLE","proof","Android")))
                .isInstanceOfSatisfying(ApiException.class,e->assertThat(e.status().value()).isEqualTo(503));
        verifyNoInteractions(accounts,sessions);
    }
    @Test void invalidInputsNeverReachProvider() {
        for(var request: new SocialAuthController.LoginRequest[]{
            new SocialAuthController.LoginRequest("EMAIL","proof","Android"),
            new SocialAuthController.LoginRequest(null,"proof","Android"),
            new SocialAuthController.LoginRequest("GOOGLE",null,"Android"),
            new SocialAuthController.LoginRequest("GOOGLE"," ","Android"),
            new SocialAuthController.LoginRequest("GOOGLE","x".repeat(16385),"Android"),
            new SocialAuthController.LoginRequest("GOOGLE","proof",null),
            new SocialAuthController.LoginRequest("GOOGLE","proof","x".repeat(201))}) {
            assertThatThrownBy(()->controller.login(request)).isInstanceOfSatisfying(ApiException.class,
                    e->assertThat(e.status().value()).isEqualTo(400));
        }
        verifyNoInteractions(google,kakao,accounts,sessions);
    }
    @Test void refreshReturnsIdentityAuthenticatedFromNewToken() {
        when(sessions.refresh("refresh",device)).thenReturn(tokens);
        when(sessions.authenticate(tokens.accessToken(),device)).thenReturn(new SessionService.Principal(user,device,UUID.randomUUID()));
        var response=controller.refresh(new SocialAuthController.RefreshRequest("refresh",device.toString()));
        assertThat(response.getBody().userId()).isEqualTo(user.toString());
        assertThat(response.getBody().refreshToken()).isEqualTo("refresh-secret");
    }
    @Test void meRequiresCanonicalDeviceAndBearer() {
        for(String id:new String[]{null,"invalid","1-1-1-1-1"}) {
            assertThatThrownBy(()->controller.me("Bearer token",id)).isInstanceOf(ApiException.class);
        }
        assertThatThrownBy(()->controller.me(null,device.toString())).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->controller.me("Basic value",device.toString())).isInstanceOf(ApiException.class);
        verifyNoInteractions(sessions);
    }
    @Test void meChecksTokenAndDeviceTogether() {
        var principal=new SessionService.Principal(user,device,UUID.randomUUID());
        when(sessions.authenticate("token",device)).thenReturn(principal);
        assertThat(controller.me("Bearer token",device.toString()).getBody()).isEqualTo(principal);
    }
    @Test void dtoStringsNeverExposeProofsOrTokens() {
        assertThat(new SocialAuthController.LoginRequest("GOOGLE","secret","Android").toString()).doesNotContain("secret");
        assertThat(new SocialAuthController.RefreshRequest("secret",device.toString()).toString()).doesNotContain("secret");
        assertThat(new SocialAuthController.LoginResponse("u","d","secret","secret","a","r").toString()).doesNotContain("secret");
    }
}
