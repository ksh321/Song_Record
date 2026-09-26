package com.ksh321.songrecord.api.auth;

import java.time.Instant;

/** Only the signed, server-verified provider result crosses this boundary. */
@FunctionalInterface
public interface LinkProofVerifier {
    VerifiedProviderIdentity verify(String provider, String proof, byte[] nonceHash, Instant startedAt);
}
