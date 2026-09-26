package com.ksh321.songrecord.api.auth;

import java.time.*;
import java.util.*;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.util.function.Consumer;
import java.util.stream.Stream;
import com.nimbusds.jose.*;
import com.nimbusds.jose.jwk.*;
import com.nimbusds.jose.jwk.gen.RSAKeyGenerator;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.*;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;

class LinkOidcVerifierTests {
    static final Instant NOW=Instant.parse("2026-09-26T00:00:00Z");
    static RSAKey key;
    static byte[] nonceHash;
    static LinkOidcVerifier verifier;
    @BeforeAll static void setup() throws Exception {
        key=new RSAKeyGenerator(2048).keyID("test").generate();
        nonceHash=MessageDigest.getInstance("SHA-256").digest("request-nonce".getBytes(StandardCharsets.UTF_8));
        verifier=new LinkOidcVerifier("KAKAO","native-app-key",Set.of("https://kauth.kakao.com"),
            new ImmutableJWKSet<>(new JWKSet(key.toPublicJWK())),Clock.fixed(NOW,ZoneOffset.UTC));
    }
    JWTClaimsSet.Builder valid(){return new JWTClaimsSet.Builder().issuer("https://kauth.kakao.com").audience("native-app-key")
        .subject("123").issueTime(Date.from(NOW)).expirationTime(Date.from(NOW.plusSeconds(3600))).claim("nonce","request-nonce");}
    String sign(JWTClaimsSet.Builder c,RSAKey k) throws Exception {
        var t=new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).keyID("test").build(),c.build());
        t.sign(new RSASSASigner(k));return t.serialize();
    }
    @Test void verifiesSignedIdentityAndNonce() throws Exception {
        assertEquals(new VerifiedProviderIdentity("KAKAO","123"),verifier.verify(sign(valid(),key),nonceHash,NOW));
    }
    record Case(String name,Consumer<JWTClaimsSet.Builder> change) {}
    @TestFactory Stream<DynamicTest> rejectsInvalidSignedClaims() {
        return Stream.of(
            new Case("wrong nonce",c->c.claim("nonce","other")),
            new Case("missing nonce",c->c.claim("nonce",null)),
            new Case("wrong audience",c->c.audience("other")),
            new Case("extra audience",c->c.audience(List.of("native-app-key","other"))),
            new Case("wrong issuer",c->c.issuer("https://example.test")),
            new Case("no subject",c->c.subject(null)),
            new Case("expired",c->c.expirationTime(Date.from(NOW))),
            new Case("old proof",c->c.issueTime(Date.from(NOW.minusSeconds(301)))),
            new Case("before challenge",c->c.issueTime(Date.from(NOW.minusSeconds(61)))),
            new Case("future proof",c->c.issueTime(Date.from(NOW.plusSeconds(61)))),
            new Case("missing issued time",c->c.issueTime(null)),
            new Case("not active",c->c.notBeforeTime(Date.from(NOW.plusSeconds(61))))
        ).map(c->DynamicTest.dynamicTest(c.name(),()->{var b=valid();c.change().accept(b);
            assertThrows(com.ksh321.songrecord.api.web.ApiException.class,()->verifier.verify(sign(b,key),nonceHash,NOW));}));
    }
    @Test void rejectsWrongSignature() throws Exception {
        var other=new RSAKeyGenerator(2048).keyID("test").generate();
        assertThrows(com.ksh321.songrecord.api.web.ApiException.class,()->verifier.verify(sign(valid(),other),nonceHash,NOW));
    }
}
