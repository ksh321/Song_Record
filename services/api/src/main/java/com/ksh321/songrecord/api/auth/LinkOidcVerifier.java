package com.ksh321.songrecord.api.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Instant;
import java.util.Set;
import com.nimbusds.jose.*;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.*;
import com.nimbusds.jwt.*;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;

/** Per-request nonce, exact audience, recent issuance and trusted keys; no email matching. */
public final class LinkOidcVerifier {
    private final DefaultJWTProcessor<SecurityContext> processor = new DefaultJWTProcessor<>();
    private final String provider;
    private final Set<String> audiences;
    private final Set<String> issuers;
    private final Clock clock;
    public LinkOidcVerifier(String provider, String audience, Set<String> issuers,
                            JWKSource<SecurityContext> keys, Clock clock) {
        this(provider,Set.of(audience),issuers,keys,clock);
    }
    public LinkOidcVerifier(String provider, Set<String> audiences, Set<String> issuers,
                            JWKSource<SecurityContext> keys, Clock clock) {
        if (audiences == null || audiences.isEmpty() || audiences.size()>2 || audiences.stream().anyMatch(a->a==null || a.isBlank()))
            throw new IllegalArgumentException("Exact OIDC audiences required");
        this.provider=provider; this.audiences=Set.copyOf(audiences); this.issuers=Set.copyOf(issuers); this.clock=clock;
        processor.setJWSKeySelector(new JWSVerificationKeySelector<>(JWSAlgorithm.RS256,keys));
        // All claim checks below use the injected clock and the specific challenge.
        processor.setJWTClaimsSetVerifier((claims, context)->{});
    }
    public VerifiedProviderIdentity verify(String proof, byte[] nonceHash, Instant startedAt) {
        if(proof==null || proof.isBlank() || proof.length()>16384) throw ProofErrors.invalid();
        try {
            var token=SignedJWT.parse(proof);
            if(!JWSAlgorithm.RS256.equals(token.getHeader().getAlgorithm()) || token.getHeader().getKeyID()==null
                    || token.getHeader().getKeyID().isBlank()) throw ProofErrors.invalid();
            var c=processor.process(token,null); var now=clock.instant();
            String nonce=c.getStringClaim("nonce");
            if(!issuers.contains(c.getIssuer()==null?"":c.getIssuer()) || c.getAudience().size()!=1 || !audiences.contains(c.getAudience().get(0))
                    || c.getSubject()==null || c.getSubject().isBlank() || c.getSubject().length()>255
                    || c.getIssueTime()==null || c.getExpirationTime()==null
                    || !c.getExpirationTime().toInstant().isAfter(now)
                    || !c.getExpirationTime().after(c.getIssueTime())
                    || c.getIssueTime().toInstant().isBefore(startedAt.minusSeconds(60))
                    || c.getIssueTime().toInstant().isBefore(now.minusSeconds(300))
                    || c.getIssueTime().toInstant().isAfter(now.plusSeconds(60))
                    || (c.getNotBeforeTime()!=null && c.getNotBeforeTime().toInstant().isAfter(now.plusSeconds(60)))
                    || nonce==null || nonce.length()>256
                    || !MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(nonce.getBytes(StandardCharsets.UTF_8)),nonceHash))
                throw ProofErrors.invalid();
            return new VerifiedProviderIdentity(provider,c.getSubject());
        } catch(java.text.ParseException | BadJOSEException | IllegalArgumentException e) {
            throw ProofErrors.invalid();
        } catch(JOSEException e) { throw ProofErrors.unavailable();
        } catch(java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
}
