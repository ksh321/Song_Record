package com.ksh321.songrecord.api.auth;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import java.util.stream.Stream;

import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.KeySourceException;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.gen.RSAKeyGenerator;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.source.JWKSourceBuilder;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jose.util.Resource;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.PlainJWT;
import com.nimbusds.jwt.SignedJWT;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;
import org.springframework.http.HttpStatus;

import com.ksh321.songrecord.api.web.ApiException;

import static org.junit.jupiter.api.Assertions.*;

class GoogleProofVerifierTests {
    private static final Instant NOW = Instant.parse("2026-09-24T00:00:00Z");
    private static final Clock CLOCK = Clock.fixed(NOW, ZoneOffset.UTC);
    private static final String AUDIENCE = "server.apps.googleusercontent.com";
    private static RSAKey key;
    private static RSAKey otherKey;
    private static GoogleProofVerifier verifier;

    @BeforeAll
    static void setup() throws Exception {
        key = new RSAKeyGenerator(2048).keyID("key-1").generate();
        otherKey = new RSAKeyGenerator(2048).keyID("key-2").generate();
        verifier = new GoogleProofVerifier(AUDIENCE,
                new ImmutableJWKSet<>(new JWKSet(key.toPublicJWK())), CLOCK);
    }

    private JWTClaimsSet.Builder validClaims() {
        return new JWTClaimsSet.Builder().issuer("https://accounts.google.com")
                .audience(AUDIENCE).subject("google-sub-123")
                .issueTime(Date.from(NOW.minusSeconds(30)))
                .expirationTime(Date.from(NOW.plusSeconds(3600)));
    }

    private String sign(JWTClaimsSet claims, RSAKey signer, String kid) throws Exception {
        SignedJWT token = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256)
                .type(JOSEObjectType.JWT).keyID(kid).build(), claims);
        token.sign(new RSASSASigner(signer));
        return token.serialize();
    }

    private void assertInvalid(String token) {
        ApiException error = assertThrows(ApiException.class, () -> verifier.verify(token));
        assertEquals(HttpStatus.UNAUTHORIZED, error.status());
        assertEquals("AUTH_INVALID_PROOF", error.code());
        assertFalse(error.retryable());
        assertNull(error.getCause());
        assertTrue(error.details().isEmpty());
    }

    @Test
    void acceptsBothGoogleIssuersAndUsesSubjectNotEmail() throws Exception {
        for (String issuer : List.of("accounts.google.com", "https://accounts.google.com")) {
            var claims = validClaims().issuer(issuer).claim("email", "not-an-account-key@example.com").build();
            assertEquals(new VerifiedProviderIdentity("GOOGLE", "google-sub-123"),
                    verifier.verify(sign(claims, key, "key-1")));
        }
    }

    record InvalidClaim(String name, Consumer<JWTClaimsSet.Builder> change) {}

    @TestFactory
    Stream<DynamicTest> rejectsInvalidClaimsWithValidSignatures() {
        return Stream.of(
                new InvalidClaim("foreign issuer", b -> b.issuer("https://attacker.example")),
                new InvalidClaim("missing issuer", b -> b.issuer(null)),
                new InvalidClaim("foreign audience", b -> b.audience("other-app")),
                new InvalidClaim("Android ID instead of server ID", b -> b.audience("android.apps.googleusercontent.com")),
                new InvalidClaim("missing audience", b -> b.audience(List.of())),
                new InvalidClaim("extra audience", b -> b.audience(List.of(AUDIENCE, "other-app"))),
                new InvalidClaim("missing subject", b -> b.subject(null)),
                new InvalidClaim("blank subject", b -> b.subject(" ")),
                new InvalidClaim("expired", b -> b.expirationTime(Date.from(NOW.minusSeconds(1)))),
                new InvalidClaim("exact expiry boundary", b -> b.expirationTime(Date.from(NOW))),
                new InvalidClaim("missing expiry", b -> b.expirationTime(null)),
                new InvalidClaim("missing issued at", b -> b.issueTime(null)),
                new InvalidClaim("future issued at", b -> b.issueTime(Date.from(NOW.plusSeconds(61)))),
                new InvalidClaim("future not before", b -> b.notBeforeTime(Date.from(NOW.plusSeconds(61)))),
                new InvalidClaim("expiry before issue", b -> b.issueTime(Date.from(NOW.plusSeconds(50)))
                        .expirationTime(Date.from(NOW.plusSeconds(40))))
        ).map(test -> DynamicTest.dynamicTest(test.name(), () -> {
            var builder = validClaims();
            test.change().accept(builder);
            assertInvalid(sign(builder.build(), key, "key-1"));
        }));
    }

    @Test
    void rejectsForgedSignatureAndUnknownKey() throws Exception {
        assertInvalid(sign(validClaims().build(), otherKey, "key-1"));
        assertInvalid(sign(validClaims().build(), otherKey, "key-2"));
        assertInvalid(sign(validClaims().build(), key, null));
    }

    @Test
    void rejectsUnsignedHmacMalformedAndOversizedInputs() throws Exception {
        assertInvalid(new PlainJWT(validClaims().build()).serialize());
        SignedJWT hmac = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.HS256).keyID("key-1").build(), validClaims().build());
        hmac.sign(new MACSigner(new byte[32]));
        assertInvalid(hmac.serialize());
        for (String input : List.of("", " ", "google-sub-123", "a.b.c", "x".repeat(16_385))) {
            assertInvalid(input);
        }
        assertInvalid(null);
    }

    @Test
    void rejectsPayloadTampering() throws Exception {
        String original = sign(validClaims().build(), key, "key-1");
        String replacement = sign(validClaims().subject("victim").build(), key, "key-1");
        String[] segments = original.split("\\.");
        assertInvalid(segments[0] + "." + replacement.split("\\.")[1] + "." + segments[2]);
    }

    @Test
    void providerOutageIsRetryableAndDoesNotLeakLibraryDetails() throws Exception {
        var unavailable = new GoogleProofVerifier(AUDIENCE, (selector, context) -> {
            throw new KeySourceException("private diagnostic should not escape");
        }, CLOCK);
        String token = sign(validClaims().build(), key, "key-1");
        ApiException error = assertThrows(ApiException.class, () -> unavailable.verify(token));
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, error.status());
        assertEquals("AUTH_PROVIDER_UNAVAILABLE", error.code());
        assertTrue(error.retryable());
        assertNull(error.getCause());
        assertFalse(error.getMessage().contains("private diagnostic"));
    }

    @Test
    void cachesKeysAndRefreshesOnNewKeyId() throws Exception {
        AtomicInteger fetches = new AtomicInteger();
        var source = JWKSourceBuilder.<SecurityContext>create(
                java.net.URI.create("https://www.googleapis.com/oauth2/v3/certs").toURL(), url -> {
                    int count = fetches.incrementAndGet();
                    return new Resource(new JWKSet(count == 1 ? key.toPublicJWK() : otherKey.toPublicJWK())
                            .toString(), "application/json");
                }).refreshAheadCache(false).rateLimited(false).build();
        try {
            var cached = new GoogleProofVerifier(AUDIENCE, source, CLOCK);
            String first = sign(validClaims().build(), key, "key-1");
            cached.verify(first);
            cached.verify(first);
            assertEquals(1, fetches.get());
            cached.verify(sign(validClaims().build(), otherKey, "key-2"));
            assertEquals(2, fetches.get());
        } finally {
            ((java.io.Closeable) source).close();
        }
    }

    @Test
    void rejectsMissingConfiguration() {
        assertThrows(IllegalArgumentException.class,
                () -> new GoogleProofVerifier(" ", new ImmutableJWKSet<>(new JWKSet()), CLOCK));
    }
}
