package com.ksh321.songrecord.api.sync;

import com.ksh321.songrecord.api.auth.AccountAccess;
import java.nio.ByteBuffer;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/** Short consistent read, followed by a fresh session check outside the read view. */
public final class ChangeReadView {
    private final DataSource source;
    private final AccountAccess access;
    private final Clock clock;
    public ChangeReadView(DataSource source,AccountAccess access,Clock clock){
        this.source=Objects.requireNonNull(source);this.access=Objects.requireNonNull(access);this.clock=Objects.requireNonNull(clock);
    }
    public ChangeWindow.Page read(AccountAccess.Account account,long after,int limit)throws SQLException {
        if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Change reads require an independent transaction");
        UUID owner=access.revalidate(account).userId();
        Instant started=clock.instant();
        long head,retained;
        var rows=new ArrayList<ChangeWindow.Entry>();
        try(var connection=source.getConnection()) {
            connection.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
            connection.setReadOnly(true);connection.setAutoCommit(false);
            try {
                try(var q=connection.prepareStatement("SELECT last_change_seq,retained_from_seq FROM user_sync_state WHERE user_id=?")) {
                    q.setQueryTimeout(15);q.setBytes(1,bytes(owner));
                    try(var result=q.executeQuery()) {
                        if(!result.next())throw new IllegalStateException("Missing account sync state");
                        head=result.getLong(1);retained=result.getLong(2);
                        if(result.next())throw new IllegalStateException("Duplicate account sync state");
                    }
                }
                ChangeWindow.checkPosition(after,head,retained,limit);
                // Retention cleanup may not have run yet. Never silently skip expired rows.
                try(var q=connection.prepareStatement("SELECT MAX(change_seq) FROM change_log WHERE user_id=? AND expires_at<=?")) {
                    q.setQueryTimeout(15);q.setBytes(1,bytes(owner));q.setObject(2,LocalDateTime.ofInstant(started,ZoneOffset.UTC));
                    try(var result=q.executeQuery()) {
                        result.next();Long expired=result.getObject(1,Long.class);
                        if(expired!=null&&expired>after)throw ChangeWindow.expired();
                    }
                }
                try(var q=connection.prepareStatement("SELECT change_seq,entity_type,entity_id,revision,operation,payload,expires_at FROM change_log WHERE user_id=? AND change_seq>? AND change_seq<=? ORDER BY change_seq LIMIT ?")) {
                    q.setQueryTimeout(15);q.setBytes(1,bytes(owner));q.setLong(2,after);q.setLong(3,head);q.setInt(4,limit+1);
                    try(var result=q.executeQuery()) {
                        while(result.next())rows.add(new ChangeWindow.Entry(result.getLong(1),
                            new AccountChanges.Change(AccountChanges.Entity.valueOf(result.getString(2)),uuid(result.getBytes(3)),result.getLong(4),
                                AccountChanges.Operation.valueOf(result.getString(5)),result.getString(6)),
                            result.getObject(7,LocalDateTime.class).toInstant(ZoneOffset.UTC)));
                    }
                }
                ChangeWindow.validate(after,head,retained,limit,rows,clock.instant());
                connection.commit();
            } catch(SQLException|RuntimeException|Error failure) {
                try{connection.rollback();}catch(SQLException rollback){failure.addSuppressed(rollback);}
                throw failure;
            }
        }
        // Do not revalidate inside REPEATABLE READ: that could see an old session.
        if(!access.revalidate(account).userId().equals(owner))throw new IllegalStateException("Account changed during change read");
        Instant finished=clock.instant();
        if(finished.isBefore(started)||!finished.isBefore(started.plusSeconds(15)))throw new IllegalStateException("Change read deadline exceeded");
        return ChangeWindow.validate(after,head,retained,limit,rows,finished);
    }
    private static byte[] bytes(UUID id){return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes){if(bytes==null||bytes.length!=16)throw new IllegalStateException("Invalid change identity");var b=ByteBuffer.wrap(bytes);return new UUID(b.getLong(),b.getLong());}
}
