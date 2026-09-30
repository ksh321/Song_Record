package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.nio.ByteBuffer;
import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.function.BiConsumer;
import javax.sql.DataSource;

/** D09 source-read boundary. A build must restart this whole view after failure. */
public final class SnapshotReadView {
    @FunctionalInterface
    public interface Reader<T> {
        /** Trusted extraction code only: plain SELECTs on this connection, no locks/writes.
         * Fully consume results before returning; no Connection/ResultSet may escape.
         * Extraction statements must use the remaining build timeout.
         */
        T read(Connection connection, UUID owner) throws SQLException;
    }
    public record Captured<T>(long cursor, Instant capturedAt, T value) {
        @Override public String toString() { return "SnapshotCapture[REDACTED]"; }
    }
    private final DataSource source;
    private final AccountAccess access;
    private final Clock clock;
    public SnapshotReadView(DataSource source, AccountAccess access, Clock clock) {
        this.source=Objects.requireNonNull(source);this.access=Objects.requireNonNull(access);this.clock=Objects.requireNonNull(clock);
    }
    public <T> Captured<T> capture(AccountAccess.Account account, Instant buildStartedAt, Reader<T> reader) throws SQLException {
        return capture(account,buildStartedAt,(cursor,time)->{},reader);
    }
    /** Records the fixed baseline before extraction batches use separate writer connections. */
    public <T> Captured<T> capture(AccountAccess.Account account, Instant buildStartedAt,
                                  BiConsumer<Long,Instant> baseline,Reader<T> reader) throws SQLException {
        return capture(SnapshotAuthority.request(access,account),buildStartedAt,baseline,reader);
    }
    <T> Captured<T> capture(SnapshotAuthority authority,Instant buildStartedAt,
                            BiConsumer<Long,Instant> baseline,Reader<T> reader) throws SQLException {
        Objects.requireNonNull(reader);Objects.requireNonNull(buildStartedAt);
        Objects.requireNonNull(baseline);
        UUID owner=authority.requireActive();
        checkDeadline(buildStartedAt);
        try(Connection connection=source.getConnection()) {
            connection.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
            connection.setReadOnly(true);
            connection.setAutoCommit(false);
            try {
                long cursor;
                // This first plain consistent SELECT establishes the InnoDB
                // read view used by every subsequent source query.
                try(var query=connection.prepareStatement("SELECT last_change_seq FROM user_sync_state WHERE user_id=?")) {
                    query.setQueryTimeout(600);
                    query.setBytes(1,ByteBuffer.allocate(16).putLong(owner.getMostSignificantBits()).putLong(owner.getLeastSignificantBits()).array());
                    try(var rows=query.executeQuery()) {
                        if(!rows.next())throw new IllegalStateException("Missing account sync state");
                        cursor=rows.getLong(1);
                        if(rows.wasNull()||cursor<0||rows.next())throw new IllegalStateException("Invalid account sync state");
                    }
                }
                Instant capturedAt=clock.instant();
                baseline.accept(cursor,capturedAt);
                T value=Objects.requireNonNull(reader.read(connection,owner));
                if(!authority.requireActive().equals(owner))throw new IllegalStateException("Account changed during snapshot capture");
                checkDeadline(buildStartedAt);
                connection.commit();
                return new Captured<>(cursor,capturedAt,value);
            } catch(SQLException|RuntimeException|Error failure) {
                try {connection.rollback();}catch(SQLException rollback){failure.addSuppressed(rollback);}
                throw failure;
            }
        }
    }
    private void checkDeadline(Instant start) {
        Instant now=clock.instant();
        if(now.isBefore(start)||!now.isBefore(start.plus(Duration.ofMinutes(10))))
            throw new IllegalStateException("Snapshot build deadline exceeded");
    }
}
