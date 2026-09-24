package com.ksh321.songrecord.api.auth;

import java.text.ParseException;
import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.Set;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.BadJOSEException;
import com.nimbusds.jose.proc.JWSVerificationKeySelector;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.nimbusds.jwt.proc.BadJWTException;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;
import org.springframework.http.HttpStatus;

import com.ksh321.songrecord.api.web.ApiException;

/** Google ID tokens only. This is not an application session-token verifier. */
public final class GoogleProofVerifier {
    private static final Set<String> ISSUERS = Set.of("accounts.google.com", "https://accounts.google.com");
    private static final int MAX_TOKEN_LENGTH = 16_384;
    private final DefaultJWTProcessor<SecurityContext> processor;

    public GoogleProofVerifier(String audience, JWKSource<SecurityContext> keys, Clock clock) {
        if (audience == null || audience.isBlank()) {
            throw new IllegalArgumentException("Google server client ID is required");
        }
        processor = new DefaultJWTProcessor<>();
        processor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.RS256, keys));
        processor.setJWTClaimsSetVerifier((claims, context) -> validateClaims(claims, audience, clock.instant()));
    }

    public VerifiedProviderIdentity verify(String idToken) {
        if (idToken == null || idToken.isBlank() || idToken.length() > MAX_TOKEN_LENGTH) {
            throw invalidProof();
        }
        try {
            SignedJWT token = SignedJWT.parse(idToken);
            if (!JWSAlgorithm.RS256.equals(token.getHeader().getAlgorithm())
                    || token.getHeader().getKeyID() == null || token.getHeader().getKeyID().isBlank()) {
                throw invalidProof();
            }
            // Keys come exclusively from the configured Google source, never a JWT jku/x5u URL.
            JWTClaimsSet claims = processor.process(token, null);
            return new VerifiedProviderIdentity("GOOGLE", claims.getSubject());
        } catch (ParseException | BadJOSEException | IllegalArgumentException exception) {
            // Do not retain the untrusted token or library exception message in API/log output.
            throw invalidProof();
        } catch (JOSEException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "AUTH_PROVIDER_UNAVAILABLE",
                    "로그인 제공자 확인이 지연되고 있습니다. 다시 시도해 주세요.", true, Map.of());
        }
    }

    private static void validateClaims(JWTClaimsSet claims, String audience, Instant now) throws BadJWTException {
        if (!ISSUERS.contains(claims.getIssuer() == null ? "" : claims.getIssuer())
                || !claims.getAudience().equals(java.util.List.of(audience))
                || claims.getSubject() == null || claims.getSubject().isBlank()
                || claims.getSubject().length() > 255
                || claims.getExpirationTime() == null || claims.getIssueTime() == null
                || !claims.getExpirationTime().toInstant().isAfter(now)
                || claims.getIssueTime().toInstant().isAfter(now.plusSeconds(60))
                || !claims.getExpirationTime().after(claims.getIssueTime())
                || (claims.getNotBeforeTime() != null
                    && claims.getNotBeforeTime().toInstant().isAfter(now.plusSeconds(60)))) {
            throw new BadJWTException("Invalid Google proof");
        }
    }

    private static ApiException invalidProof() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_INVALID_PROOF",
                "로그인 정보를 확인할 수 없습니다. 다시 로그인해 주세요.", false, Map.of());
    }
}
