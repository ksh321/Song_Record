package com.ksh321.songrecord.api.auth;

/** Only constructed from a server-verified proof; email is not an account key. */
public record VerifiedProviderIdentity(String provider, String providerUserId) {
}
