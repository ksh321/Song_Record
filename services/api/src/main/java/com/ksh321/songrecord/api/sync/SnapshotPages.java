package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;

/** Reads immutable, published D09 rows only. Does not build or expose partial snapshots. */
public final class SnapshotPages {
    public enum Entity {
        SONG, SONG_SOURCE, RECORDING, RECORDING_FILE_SPEC, RECORDING_ASSET,
        PLAYLIST, PLAYLIST_ITEM, TAG, RECORDING_TAG, RECORDING_CONDITION,
        USER_ENTITLEMENT, STORAGE_USAGE, SONG_CLOUD_SELECTION, PIN_SLOT,
        USER_SYNC_STATE, CHANGE_LOG, DELETION_BATCH, DELETION_ITEM, DELETION_LEDGER
    }
    public record Entry(long ordinal, UUID resourceId, String payload) {
        @Override public String toString() { return "SnapshotEntry[REDACTED]"; }
    }
    public record Page(UUID snapshotToken, long snapshotCursor, Instant expiresAt,
                       Entity entity, List<Entry> entries, String nextCursor) {
        public Page { entries = List.copyOf(entries); }
        @Override public String toString() { return "SnapshotPage[REDACTED]"; }
    }
    private record Header(String status, Long cursor, Instant expiry) {}
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final SnapshotPageCursor cursors;
    private final Clock clock;

    public SnapshotPages(JdbcTemplate jdbc, AccountAccess access, SnapshotPageCursor cursors, Clock clock) {
        this.jdbc=Objects.requireNonNull(jdbc);this.access=Objects.requireNonNull(access);
        this.cursors=Objects.requireNonNull(cursors);this.clock=Objects.requireNonNull(clock);
    }
    public Page read(AccountAccess.Account account, UUID token, Entity entity, String cursor, Integer requestedLimit) {
        Objects.requireNonNull(token);Objects.requireNonNull(entity);
        int limit = requestedLimit == null ? 50 : requestedLimit;
        if (limit < 1 || limit > 100) throw failure(HttpStatus.BAD_REQUEST,"VALIDATION_ERROR");
        var owner = access.revalidate(account).userId();
        var header = ready(owner, token);
        long after = cursor == null ? 0 : cursors.read(cursor, owner, token, entity.name(), header.expiry);
        var rows = jdbc.query("SELECT ordinal,resource_id,payload FROM snapshot_entry WHERE snapshot_id=? AND entity=? AND ordinal>? ORDER BY ordinal LIMIT ?",
                (rs,n) -> new Entry(rs.getLong(1), uuid(rs.getBytes(2)), rs.getString(3)),
                bytes(token), entity.name(), after, limit+1);
        boolean more = rows.size() > limit;
        var entries = List.copyOf(rows.subList(0, Math.min(limit, rows.size())));
        // Session revocation and expiry while reading must not release a page.
        if (!access.revalidate(account).userId().equals(owner)) throw failure(HttpStatus.UNAUTHORIZED,"AUTH_INVALID_SESSION");
        var current = ready(owner, token);
        if (!current.equals(header)) throw failure(HttpStatus.CONFLICT,"SNAPSHOT_NOT_READY");
        String next = more ? cursors.issue(owner, token, entity.name(), entries.getLast().ordinal(), header.expiry) : null;
        return new Page(token, header.cursor, header.expiry, entity, entries, next);
    }
    private Header ready(UUID owner, UUID token) {
        var rows = jdbc.query("SELECT status,snapshot_cursor,expires_at FROM snapshot_header WHERE user_id=? AND id=? AND purpose='SYNC'",
                (rs,n) -> new Header(rs.getString(1), rs.getObject(2,Long.class),
                        rs.getTimestamp(3) == null ? null : rs.getTimestamp(3).toLocalDateTime().toInstant(ZoneOffset.UTC)),
                bytes(owner), bytes(token));
        if (rows.isEmpty()) throw failure(HttpStatus.NOT_FOUND,"SNAPSHOT_NOT_FOUND");
        var header = rows.getFirst();
        if (header.status.equals("EXPIRED") || header.expiry != null && !clock.instant().isBefore(header.expiry))
            throw failure(HttpStatus.GONE,"SNAPSHOT_EXPIRED");
        if (!header.status.equals("READY") || header.cursor == null || header.expiry == null)
            throw failure(HttpStatus.CONFLICT,"SNAPSHOT_NOT_READY");
        return header;
    }
    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }
    private static UUID uuid(byte[] value) {
        var b = ByteBuffer.wrap(value); return new UUID(b.getLong(),b.getLong());
    }
    private static ApiException failure(HttpStatus status,String code) {
        return new ApiException(status,code,"스냅샷 상태와 조회 조건을 확인해 주세요.",false,Map.of());
    }
}
