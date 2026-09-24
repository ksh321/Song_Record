package com.ksh321.songrecord.api.auth;

import java.util.UUID;

/** Existing account link. Its presence does not itself authorize a session. */
public record AuthIdentity(UUID id, UUID userId, String provider, String providerUserId) {}
