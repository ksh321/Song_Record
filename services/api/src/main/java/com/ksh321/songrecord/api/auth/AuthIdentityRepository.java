package com.ksh321.songrecord.api.auth;

import java.util.Optional;

public interface AuthIdentityRepository {
    Optional<AuthIdentity> find(VerifiedProviderIdentity identity);
}
