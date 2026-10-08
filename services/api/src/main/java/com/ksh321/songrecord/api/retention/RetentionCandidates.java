package com.ksh321.songrecord.api.retention;

import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.uuid;

/** Server-internal candidate read. Callers supply the authenticated/job owner, never a client owner override.
 * Eligibility is independent of asset storage, device availability, key, version and tier.
 * This read neither selects roles nor schedules uploads/deletions or changes selection_revision. */
@Component
@Profile("!bootstrap")
public final class RetentionCandidates {
    private final JdbcTemplate jdbc;
    public RetentionCandidates(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public List<Candidate> forSong(UUID owner, UUID song) {
        return query(owner, song, false);
    }

    List<Candidate> forRepresentative(UUID owner, UUID song) {
        return query(owner, song, true);
    }

    private List<Candidate> query(UUID owner, UUID song, boolean representativeOnly) {
        Objects.requireNonNull(owner, "owner");
        Objects.requireNonNull(song, "song");
        return jdbc.query("""
            SELECT r.id, r.origin_device_id, r.recorded_at, r.tier, r.revision, r.link_revision,
                   f.sha256, f.size_bytes, f.duration_ms, f.codec, f.sample_rate, f.channels, f.capture_integrity
            FROM recording r
            JOIN song s ON s.id = r.song_id AND s.user_id = r.user_id
            JOIN app_user u ON u.id = r.user_id
            JOIN recording_file_spec f ON f.recording_id = r.id AND f.user_id = r.user_id
            WHERE r.user_id = ? AND r.song_id = ?
              AND u.status = 'ACTIVE' AND s.lifecycle_state = 'ACTIVE'
              AND r.lifecycle_state = 'ACTIVE' AND r.metadata_state = 'SAVED'
            """ + (representativeOnly ? " AND s.representative_recording_id = r.id" : "") + " ORDER BY r.id", (rs, row) -> new Candidate(uuid(rs.getBytes("id")), uuid(rs.getBytes("origin_device_id")),
                rs.getTimestamp("recorded_at").toLocalDateTime().toInstant(ZoneOffset.UTC),
                rs.getString("tier"), rs.getLong("revision"), rs.getLong("link_revision"),
                new FileSpec(rs.getString("sha256"), rs.getLong("size_bytes"), rs.getInt("duration_ms"),
                    rs.getString("codec"), rs.getInt("sample_rate"), rs.getInt("channels"),
                    rs.getString("capture_integrity"))), bytes(owner), bytes(song))
            .stream().filter(candidate -> candidate.file().valid()).toList();
    }

    public record Candidate(UUID recordingId, UUID originDeviceId, Instant recordedAt,
                            String tier, long revision, long linkRevision, FileSpec file) {}
    public record FileSpec(String sha256, long sizeBytes, int durationMs, String codec,
                           int sampleRate, int channels, String captureIntegrity) {
        // Same completion contract as RecordingSaving and V2; reject damaged/incomplete imported rows too.
        public boolean valid() {
            return sha256 != null && sha256.matches("[0-9a-f]{64}")
                && sizeBytes >= 1 && sizeBytes <= 6291456 && durationMs >= 1 && durationMs <= 361000
                && "AAC_LC".equals(codec) && sampleRate == 48000 && channels == 1
                && ("VALIDATED".equals(captureIntegrity) || "RECOVERED".equals(captureIntegrity));
        }
    }
}
