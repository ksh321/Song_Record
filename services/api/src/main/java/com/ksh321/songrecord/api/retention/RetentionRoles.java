package com.ksh321.songrecord.api.retention;

import java.util.Optional;
import java.util.Comparator;
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

    public Optional<Selection> latest(UUID owner, UUID song) {
        // Canonical UUID text sorts like unsigned BINARY(16); UUID.compareTo uses signed longs.
        var order = Comparator.comparing(RetentionCandidates.Candidate::recordedAt).reversed()
            .thenComparing(candidate -> candidate.recordingId().toString());
        return candidates.forSong(owner, song).stream().min(order)
            .map(candidate -> new Selection(Role.LATEST, candidate));
    }

    public Optional<Selection> lowestTier(UUID owner, UUID song) {
        var timeAndId = Comparator.comparing(RetentionCandidates.Candidate::recordedAt).reversed()
            .thenComparing(candidate -> candidate.recordingId().toString());
        var order = Comparator.comparingInt((RetentionCandidates.Candidate c) -> tierRank(c.tier()))
            .thenComparing(timeAndId);
        return candidates.forSong(owner, song).stream().filter(c -> tierRank(c.tier()) >= 0).min(order)
            .map(candidate -> new Selection(Role.LOWEST_TIER, candidate));
    }

    private static int tierRank(String tier) {
        if (tier == null) return -1;
        return switch (tier) { case "D" -> 0; case "C" -> 1; case "B" -> 2;
            case "A" -> 3; case "S" -> 4; default -> -1; };
    }

    public enum Role { REPRESENTATIVE, LATEST, LOWEST_TIER }
    public record Selection(Role role, RetentionCandidates.Candidate candidate) {}
}
