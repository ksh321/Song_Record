package com.ksh321.songrecord.api.pagination;

import java.nio.ByteBuffer;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;

/** Real parameterized SQL adapter for the common pager; no mock list slicing. */
public class PageTestSource implements KeysetPages.Source<UUID> {
    public Runnable afterCount = () -> {};
    public long count(JdbcTemplate jdbc, UUID owner) {
        long count = jdbc.queryForObject("SELECT COUNT(*) FROM page_item WHERE user_id=?", Long.class, bytes(owner));
        afterCount.run(); return count;
    }
    public List<KeysetPages.Entry<UUID>> fetch(JdbcTemplate jdbc, UUID owner, PageCursor.Tuple after, int maximum) {
        var args = new ArrayList<Object>(); args.add(bytes(owner));
        String condition = "";
        if (after != null) {
            int rank = Integer.parseInt(after.values().getFirst());
            condition = " AND (rank_no < ? OR (rank_no = ? AND id > ?))";
            args.add(rank); args.add(rank); args.add(bytes(after.id()));
        }
        args.add(maximum);
        return jdbc.query("SELECT id,rank_no FROM page_item WHERE user_id=?" + condition + " ORDER BY rank_no DESC,id ASC LIMIT ?",
                (rs, n) -> { var b = ByteBuffer.wrap(rs.getBytes(1)); var id = new UUID(b.getLong(), b.getLong());
                    return new KeysetPages.Entry<>(id, new PageCursor.Tuple(List.of(rs.getString(2)), id)); }, args.toArray());
    }
    public Comparator<PageCursor.Tuple> order() {
        return Comparator.<PageCursor.Tuple>comparingInt(t -> Integer.parseInt(t.values().getFirst())).reversed()
                .thenComparing(PageCursor.Tuple::id, KeysetPages::compareUuid);
    }
    public static byte[] bytes(UUID id) { return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array(); }
}
