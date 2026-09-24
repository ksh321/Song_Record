package com.ksh321.songrecord.api.auth;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;
import com.ksh321.songrecord.api.web.ApiException;
import static org.junit.jupiter.api.Assertions.*;

class KakaoProofVerifierTests {
    private static final long APP = 1586938;

    static KakaoTokenInfoClient.Response response(int status, String body) {
        return new KakaoTokenInfoClient.Response(status, body.getBytes(StandardCharsets.UTF_8));
    }

    private KakaoProofVerifier verifier(int status, String body) {
        return new KakaoProofVerifier(APP, token -> response(status, body));
    }

    private void fails(KakaoProofVerifier verifier, String token, String code, int status, boolean retryable) {
        ApiException error = assertThrows(ApiException.class, () -> verifier.verify(token));
        assertEquals(code, error.code());
        assertEquals(status, error.status().value());
        assertEquals(retryable, error.retryable());
        assertTrue(error.details().isEmpty());
        assertNull(error.getCause());
        assertFalse(error.getMessage().contains("private-token"));
    }

    @Test
    void validTokenUsesExactLongMemberIdNotEmail() {
        assertEquals(new VerifiedProviderIdentity("KAKAO", "9007199254740993"),
                verifier(200, """
                    {"id":9007199254740993,"app_id":1586938,"expires_in":3600,"email":"same@example.com"}
                    """).verify("private-token"));
    }

    @TestFactory
    Stream<DynamicTest> wrongAppAndExpiredTokens() {
        return Stream.of(
                "{\"id\":1,\"app_id\":99,\"expires_in\":3600}",
                "{\"id\":1,\"app_id\":1586938,\"expires_in\":0}",
                "{\"id\":1,\"app_id\":1586938,\"expires_in\":-1}"
        ).map(body -> DynamicTest.dynamicTest(body, () -> fails(verifier(200, body), "private-token",
                "AUTH_INVALID_PROOF", 401, false)));
    }

    @TestFactory
    Stream<DynamicTest> invalidProviderResponsesFailClosed() {
        return Stream.of("", "not-json", "null", "[]", "{}",
                "{\"id\":1,\"app_id\":1586938}",
                "{\"id\":1,\"appId\":1586938,\"expiresInMillis\":3600000}",
                "{\"id\":\"123\",\"app_id\":1586938,\"expires_in\":3600}",
                "{\"id\":1.5,\"app_id\":1586938,\"expires_in\":3600}",
                "{\"id\":9223372036854775808,\"app_id\":1586938,\"expires_in\":3600}",
                "{\"id\":0,\"app_id\":1586938,\"expires_in\":3600}",
                "{\"id\":1,\"app_id\":\"1586938\",\"expires_in\":3600}",
                "{\"id\":1,\"app_id\":1586938,\"expires_in\":null}",
                "{\"id\":1,\"app_id\":1586938,\"expires_in\":1.5}",
                "{\"id\":1,\"id\":2,\"app_id\":1586938,\"expires_in\":3600}",
                "{\"id\":1,\"app_id\":1586938,\"expires_in\":3600} {}")
                .map(body -> DynamicTest.dynamicTest("reject " + body, () ->
                        fails(verifier(200, body), "private-token", "AUTH_PROVIDER_UNAVAILABLE", 503, true)));
    }

    @TestFactory
    Stream<DynamicTest> statusesHaveCommonErrorContract() {
        record Case(int status, String body, boolean invalid) {}
        return Stream.of(new Case(401, "not-json", true), new Case(400, "{\"code\":-401}", true),
                new Case(400, "{\"code\":-2}", true), new Case(400, "{\"code\":-1}", false),
                new Case(400, "{\"code\":-999}", false), new Case(400, "{}", false),
                new Case(403, "{}", false), new Case(429, "{}", false),
                new Case(500, "private-token", false), new Case(302, "{}", false))
                .map(c -> DynamicTest.dynamicTest(c.status() + " " + c.body(), () ->
                        fails(verifier(c.status(), c.body()), "private-token",
                                c.invalid() ? "AUTH_INVALID_PROOF" : "AUTH_PROVIDER_UNAVAILABLE",
                                c.invalid() ? 401 : 503, !c.invalid())));
    }

    @Test
    void rejectsBadInputWithoutNetworkRequest() {
        AtomicInteger calls = new AtomicInteger();
        var verifier = new KakaoProofVerifier(APP, token -> { calls.incrementAndGet(); return response(401, "{}"); });
        for (String token : new String[]{null, "", " ", "Bearer private-token", "a\r\nb", "가", "x".repeat(4097)}) {
            fails(verifier, token, "AUTH_INVALID_PROOF", 401, false);
        }
        assertEquals(0, calls.get());
    }

    @Test
    void neverDecodesGoogleJwtAsKakaoIdentity() {
        String googleLike = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature";
        fails(verifier(401, "{\"code\":-401}"), googleLike, "AUTH_INVALID_PROOF", 401, false);
    }

    @Test
    void ioFailureIsRetryable() {
        fails(new KakaoProofVerifier(APP, token -> { throw new IOException("private-token"); }),
                "private-token", "AUTH_PROVIDER_UNAVAILABLE", 503, true);
    }

    @Test
    void interruptedCallRestoresInterruptFlag() {
        try {
            fails(new KakaoProofVerifier(APP, token -> { throw new InterruptedException(); }),
                    "private-token", "AUTH_PROVIDER_UNAVAILABLE", 503, true);
            assertTrue(Thread.currentThread().isInterrupted());
        } finally { Thread.interrupted(); }
    }

    @Test
    void missingAppIdIsConfigurationError() {
        assertThrows(IllegalArgumentException.class, () -> verifierWithApp(0));
    }

    private KakaoProofVerifier verifierWithApp(long app) {
        return new KakaoProofVerifier(app, token -> response(401, "{}"));
    }
}
