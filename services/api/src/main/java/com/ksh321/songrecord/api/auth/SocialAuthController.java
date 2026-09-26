package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.web.ApiException;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/** Provider proofs enter only here. Client user IDs can never issue sessions. */
@RestController
@Profile("!bootstrap")
@RequestMapping("/v1/auth")
public class SocialAuthController {
    private final ObjectProvider<GoogleProofVerifier> google;
    private final ObjectProvider<KakaoProofVerifier> kakao;
    private final AccountRegistrationService registration;
    private final SessionService sessions;
    public SocialAuthController(ObjectProvider<GoogleProofVerifier> google,ObjectProvider<KakaoProofVerifier> kakao,
            AccountRegistrationService registration,SessionService sessions) {
        this.google=google;this.kakao=kakao;this.registration=registration;this.sessions=sessions;
    }
    @PostMapping("/social")
    public ResponseEntity<LoginResponse> login(@RequestBody LoginRequest request) {
        if(request.proof()==null || request.proof().isBlank() || request.proof().length()>16384
                || request.deviceName()==null || request.deviceName().isBlank() || request.deviceName().length()>200) throw invalid();
        VerifiedProviderIdentity identity;
        if("GOOGLE".equals(request.provider())) {
            var verifier=google.getIfAvailable();if(verifier==null)throw ProofErrors.unavailable();
            identity=verifier.verify(request.proof());
        } else if("KAKAO".equals(request.provider())) {
            var verifier=kakao.getIfAvailable();if(verifier==null)throw ProofErrors.unavailable();
            identity=verifier.verify(request.proof());
        } else throw invalid();
        // New server-generated device per fresh provider login; never reuse another account's hint.
        var account=registration.register(identity,null,request.deviceName());
        return ok(response(account.userId(),account.deviceId(),sessions.issue(account)));
    }
    @PostMapping("/refresh")
    public ResponseEntity<LoginResponse> refresh(@RequestBody RefreshRequest request) {
        var device=parseUuid(request.deviceId());
        var tokens=sessions.refresh(request.refreshToken(),device);
        var owner=sessions.authenticate(tokens.accessToken(),device);
        return ok(response(owner.userId(),device,tokens));
    }
    @PostMapping("/logout")
    public ResponseEntity<?> logout(@RequestBody RefreshRequest request) {
        sessions.logout(request.refreshToken(),parseUuid(request.deviceId()));
        return ok(Map.of("loggedOut",true));
    }
    @GetMapping("/me")
    public ResponseEntity<SessionService.Principal> me(
            @RequestHeader(value="Authorization",required=false) String authorization,
            @RequestHeader(value="X-Device-Id",required=false) String device) {
        return ok(new AccountAccess(sessions).authenticate(authorization,device).principal());
    }
    private static LoginResponse response(UUID user,UUID device,SessionService.Tokens tokens) {
        return new LoginResponse(user.toString(),device.toString(),tokens.accessToken(),tokens.refreshToken(),
                tokens.accessExpiresAt().toInstant(ZoneOffset.UTC).toString(),tokens.refreshExpiresAt().toInstant(ZoneOffset.UTC).toString());
    }
    private static <T> ResponseEntity<T> ok(T body) {return ResponseEntity.ok().header("Cache-Control","no-store").header("Pragma","no-cache").body(body);}
    private static UUID parseUuid(String value) {
        try {var id=UUID.fromString(value);if(!id.toString().equals(value))throw unauthorized();return id;}
        catch(IllegalArgumentException | NullPointerException e){throw unauthorized();}
    }
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","로그인 요청을 확인해 주세요.",false,Map.of());}
    private static ApiException unauthorized(){return new ApiException(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION","다시 로그인해 주세요.",false,Map.of());}
    public record LoginRequest(String provider,String proof,String deviceName) {
        @Override public String toString(){return "LoginRequest[REDACTED]";}
    }
    public record RefreshRequest(String refreshToken,String deviceId) {
        @Override public String toString(){return "RefreshRequest[REDACTED]";}
    }
    public record LoginResponse(String userId,String deviceId,String accessToken,String refreshToken,String accessExpiresAt,String refreshExpiresAt) {
        @Override public String toString(){return "LoginResponse[REDACTED]";}
    }
}
