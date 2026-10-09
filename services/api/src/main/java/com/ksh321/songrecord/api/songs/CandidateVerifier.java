package com.ksh321.songrecord.api.songs;

import java.time.Instant;
import java.util.Objects;

/** Implementations authenticate source_token and obtain originals from a trusted server source. */
public interface CandidateVerifier {
    Verified verify(String sourceToken);
    /** Bounded source refresh before a mutation transaction. */
    default Verified prepare(String sourceToken, java.util.UUID owner) { return verify(sourceToken); }
    enum Brand { TJ, KY }
    record Verified(String provider, Brand brand, String number, String title, String artist,
                    Instant issuedAt, Instant expiresAt) {
        public Verified {
            Objects.requireNonNull(brand);Objects.requireNonNull(issuedAt);Objects.requireNonNull(expiresAt);
            if(provider==null || provider.isBlank() || number==null || !number.matches("[0-9]{1,20}")
                    || title==null || title.isBlank() || artist==null || artist.isBlank()
                    || title.codePointCount(0,title.length())>200 || artist.codePointCount(0,artist.length())>200)
                throw new IllegalArgumentException("Invalid verified candidate");
        }
        @Override public String toString(){return "VerifiedCandidate[REDACTED]";}
    }
}
