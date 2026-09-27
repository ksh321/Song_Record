package com.ksh321.songrecord.api.pagination;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.nio.ByteBuffer;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;

/** One short consistent read per page. Domain adapters supply parameterized keyset SQL, never OFFSET. */
public final class KeysetPages {
    public record Entry<T>(T item, PageCursor.Tuple key) {}
    public record Page<T>(List<T> items, long count, String next_cursor) {
        public Page { items = List.copyOf(items); }
        @Override public String toString() { return "Page[REDACTED]"; }
    }
    /** Use only this JdbcTemplate, plain consistent SELECTs, and the same account/filters in both queries. */
    public interface Source<T> {
        long count(JdbcTemplate jdbc, UUID owner);
        List<Entry<T>> fetch(JdbcTemplate jdbc, UUID owner, PageCursor.Tuple after, int maximum);
        Comparator<PageCursor.Tuple> order(); // Full domain ordering, ending with unsigned UUID.
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final PageCursor cursors;
    private final TransactionTemplate read;
    public KeysetPages(JdbcTemplate jdbc, AccountAccess access, PlatformTransactionManager manager, PageCursor cursors) {
        this.jdbc = jdbc; this.access = access; this.cursors = cursors;
        read = new TransactionTemplate(manager); read.setReadOnly(true);
        read.setIsolationLevel(TransactionDefinition.ISOLATION_REPEATABLE_READ); read.setTimeout(15);
    }
    public <T> Page<T> query(AccountAccess.Account account, PageCursor.Query query, String cursor, Source<T> source) {
        if (TransactionSynchronizationManager.isActualTransactionActive()) throw new IllegalStateException("Paging requires its own read transaction");
        // Validate the current session before opening the list read view.
        var owner = access.revalidate(account).userId();
        var position = cursor == null ? null : cursors.read(cursor, owner, query);
        return read.execute(status -> {
            var generations = jdbc.query("SELECT last_change_seq FROM user_sync_state WHERE user_id=?",
                    (rs, n) -> rs.getLong(1), bytes(owner));
            if (generations.size() != 1) throw new IllegalStateException("Account sync state is missing");
            long generation = generations.getFirst();
            if (position != null && position.generation() != generation) throw PageCursor.expired();
            long count = source.count(jdbc, owner);
            var after = position == null ? null : position.after();
            var rows = source.fetch(jdbc, owner, after, query.limit() + 1);
            if (count < 0 || rows.size() > query.limit() + 1 || rows.size() > count) throw new IllegalStateException("Invalid page source result");
            var previous = after;
            for (var row : rows) {
                Objects.requireNonNull(row.item()); Objects.requireNonNull(row.key());
                if (previous != null && source.order().compare(previous, row.key()) >= 0) throw new IllegalStateException("Unstable page source ordering");
                previous = row.key();
            }
            boolean more = rows.size() > query.limit();
            var returned = rows.subList(0, Math.min(rows.size(), query.limit()));
            String next = more ? cursors.issue(owner, query, generation, returned.getLast().key()) : null;
            return new Page<>(returned.stream().map(Entry::item).toList(), count, next);
        });
    }
    public static int compareUuid(UUID left, UUID right) { return left.toString().compareTo(right.toString()); }
    private static byte[] bytes(UUID id) { return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array(); }
}
