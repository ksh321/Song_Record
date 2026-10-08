package com.ksh321.songrecord.api.retention;

import java.util.*;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/** Role calculation only; selection persistence is separate from physical storage and scheduling. */
@Component
@Profile("!bootstrap")
public final class RetentionRoles {
    private final RetentionCandidates candidates;
    private static final Comparator<RetentionCandidates.Candidate> NEWEST =
        Comparator.comparing(RetentionCandidates.Candidate::recordedAt).reversed()
            .thenComparing(candidate -> candidate.recordingId().toString());
    public RetentionRoles(RetentionCandidates candidates) { this.candidates = candidates; }

    public Optional<Selection> representative(UUID owner, UUID song) {
        return candidates.forRepresentative(owner, song).stream().findFirst()
            .map(candidate -> new Selection(Role.REPRESENTATIVE, candidate));
    }
    public Optional<Selection> latest(UUID owner, UUID song) {
        return latest(candidates.forSong(owner, song)).map(c -> new Selection(Role.LATEST, c));
    }
    public Optional<Selection> lowestTier(UUID owner, UUID song) {
        return lowest(candidates.forSong(owner, song)).map(c -> new Selection(Role.LOWEST_TIER, c));
    }
    private static Optional<RetentionCandidates.Candidate> latest(List<RetentionCandidates.Candidate> rows) {
        // Canonical UUID text sorts like unsigned BINARY(16); UUID.compareTo uses signed longs.
        return rows.stream().min(NEWEST);
    }
    private static Optional<RetentionCandidates.Candidate> lowest(List<RetentionCandidates.Candidate> rows) {
        return rows.stream().filter(c -> tierRank(c.tier()) >= 0)
            .min(Comparator.comparingInt((RetentionCandidates.Candidate c) -> tierRank(c.tier())).thenComparing(NEWEST));
    }
    static Ids calculate(List<RetentionCandidates.Candidate> rows, UUID representative) {
        UUID rep=rows.stream().filter(c -> c.recordingId().equals(representative))
            .map(RetentionCandidates.Candidate::recordingId).findFirst().orElse(null);
        return new Ids(rep, latest(rows).map(RetentionCandidates.Candidate::recordingId).orElse(null),
                           lowest(rows).map(RetentionCandidates.Candidate::recordingId).orElse(null));
    }
    private static int tierRank(String tier) {
        if (tier == null) return -1;
        return switch (tier) { case "D" -> 0; case "C" -> 1; case "B" -> 2;
            case "A" -> 3; case "S" -> 4; default -> -1; };
    }
    public record Ids(UUID representative, UUID latest, UUID lowestTier) {
        public Set<UUID> recordingIds() {
            var ids=new HashSet<UUID>();
            for(UUID id:new UUID[]{representative,latest,lowestTier}) if(id!=null)ids.add(id);
            return Set.copyOf(ids);
        }
    }
    public enum Role { REPRESENTATIVE, LATEST, LOWEST_TIER }
    public record Selection(Role role, RetentionCandidates.Candidate candidate) {}
}
