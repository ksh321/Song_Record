package com.ksh321.songrecord.api.retention;

import java.util.Optional;
import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/** Read-only role calculation. Persistence/revision and scheduling belong to P11-05/06. */
@Component
@Profile("!bootstrap")
public final class RetentionRoles {
    private final RetentionCandidates candidates;
    public RetentionRoles(RetentionCandidates candidates) { this.candidates = candidates; }

    public Optional<Selection> representative(UUID owner, UUID song) {
        // Pointer and eligibility are read in one SQL statement. Never fall back to a different file.
        return candidates.forRepresentative(owner, song).stream().findFirst()
            .map(candidate -> new Selection(Role.REPRESENTATIVE, candidate));
    }

    public enum Role { REPRESENTATIVE }
    public record Selection(Role role, RetentionCandidates.Candidate candidate) {}
}
