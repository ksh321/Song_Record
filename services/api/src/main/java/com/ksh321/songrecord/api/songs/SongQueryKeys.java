package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.domain.DomainOrdering;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;

/** V1 derived data: insert in the same transaction as the owning song. Keep V11 backfill compatible. */
public final class SongQueryKeys {
    public static final String VERSION = DomainOrdering.SORT_KEY_VERSION + "/" + DomainOrdering.SORT_BYTES_VERSION;
    private SongQueryKeys() {}
    public static void insert(JdbcTemplate jdbc, UUID owner, UUID song, String title, String artist) {
        jdbc.update("INSERT INTO song_query_key(song_id,user_id,key_version,title_key,artist_key,title_search,artist_search) VALUES(?,?,?,?,?,?,?)",
                bytes(song),bytes(owner),VERSION,DomainOrdering.sortKeyBytes(title),DomainOrdering.sortKeyBytes(artist),search(title),search(artist));
    }
    public static byte[] search(String text) { return DomainOrdering.normalizeText(text).getBytes(StandardCharsets.UTF_8); }
    public static byte[] bytes(UUID value) { return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array(); }
    public static UUID uuid(byte[] bytes) { var b=ByteBuffer.wrap(bytes); return new UUID(b.getLong(),b.getLong()); }
}
