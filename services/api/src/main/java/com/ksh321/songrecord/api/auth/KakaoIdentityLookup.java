package com.ksh321.songrecord.api.auth;

import java.util.Optional;

/** Verifies first, then reads the link. No email matching, registration, or session issuance. */
public final class KakaoIdentityLookup {
    private final KakaoProofVerifier verifier;
    private final AuthIdentityRepository identities;

    public KakaoIdentityLookup(KakaoProofVerifier verifier, AuthIdentityRepository identities) {
        this.verifier = verifier;
        this.identities = identities;
    }

    public Result verifyAndFind(String accessToken) {
        VerifiedProviderIdentity verified = verifier.verify(accessToken);
        return new Result(verified, identities.find(verified));
    }

    public record Result(VerifiedProviderIdentity verified, Optional<AuthIdentity> existingIdentity) {}
}
