package com.ksh321.songrecord.api.ownership;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;

/** Ownership only: lifecycle eligibility and transactional mutation belong to domain services. */
public final class OwnershipGuard {
    public enum Resource {
        SONG("SELECT 1 FROM song WHERE user_id=? AND id=?"),
        RECORDING("SELECT 1 FROM recording WHERE user_id=? AND id=?"),
        PLAYLIST("SELECT 1 FROM playlist WHERE user_id=? AND id=?"),
        TAG("SELECT 1 FROM tag WHERE user_id=? AND id=?"),
        DEVICE("SELECT 1 FROM device WHERE user_id=? AND id=?"),
        RECORDING_ASSET("SELECT 1 FROM recording_asset a JOIN recording r ON r.user_id=a.user_id AND r.id=a.recording_id WHERE a.user_id=? AND a.recording_id=?"),
        UPLOAD("SELECT 1 FROM recording_upload u JOIN recording r ON r.user_id=u.user_id AND r.id=u.recording_id WHERE u.user_id=? AND u.id=?");
        private final String sql;
        Resource(String sql) { this.sql = sql; }
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    public OwnershipGuard(JdbcTemplate jdbc, AccountAccess access) {
        this.jdbc = jdbc; this.access = access;
    }

    public void require(AccountAccess.Account account, Resource resource, String id) {
        var owner = access.revalidate(account);
        check(resource.sql, bytes(owner.userId()), bytes(resourceId(id)));
    }

    /** Existing relation: both endpoints and the relation must belong to this account. */
    public void requireRecordingForSong(AccountAccess.Account account, String song, String recording) {
        var owner = access.revalidate(account);
        check("SELECT 1 FROM recording r JOIN song s ON s.user_id=r.user_id AND s.id=r.song_id WHERE r.user_id=? AND s.id=? AND r.id=?",
                bytes(owner.userId()), bytes(resourceId(song)), bytes(resourceId(recording)));
    }

    public void requirePlaylistItem(AccountAccess.Account account, String playlist, String item) {
        var owner = access.revalidate(account);
        check("SELECT 1 FROM playlist_item i JOIN playlist p ON p.user_id=i.user_id AND p.id=i.playlist_id LEFT JOIN song s ON s.user_id=i.user_id AND s.id=i.song_id WHERE i.user_id=? AND p.id=? AND i.id=? AND (i.song_id IS NULL OR s.id IS NOT NULL)",
                bytes(owner.userId()), bytes(resourceId(playlist)), bytes(resourceId(item)));
    }

    public void requireRecordingTag(AccountAccess.Account account, String recording, String tag) {
        var owner = access.revalidate(account);
        check("SELECT 1 FROM recording_tag rt JOIN recording r ON r.user_id=rt.user_id AND r.id=rt.recording_id JOIN tag t ON t.user_id=rt.user_id AND t.id=rt.tag_id WHERE rt.user_id=? AND r.id=? AND t.id=?",
                bytes(owner.userId()), bytes(resourceId(recording)), bytes(resourceId(tag)));
    }

    private void check(String sql, Object... args) {
        if (jdbc.query(sql, (rs, row) -> 1, args).isEmpty()) throw notFound();
    }
    private static UUID resourceId(String value) {
        try {
            var id = UUID.fromString(value);
            if (!id.toString().equals(value)) throw notFound();
            return id;
        } catch (IllegalArgumentException | NullPointerException e) { throw notFound(); }
    }
    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "RESOURCE_NOT_FOUND",
                "요청한 자료를 찾을 수 없습니다.", false, Map.of());
    }
}
