package com.ksh321.songrecord.api.revision;

import com.ksh321.songrecord.api.auth.AccountAccess;
import com.ksh321.songrecord.api.locking.LockOrder;
import com.ksh321.songrecord.api.web.ApiException;
import java.nio.ByteBuffer;
import java.sql.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.function.Consumer;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.*;
import org.springframework.transaction.support.*;

/** A database-only edit inside the caller's mutation transaction. */
public final class RevisionChanges {
    public enum Resource {
        SONG("song", "source_type,tj_number,title,artist,version_code,note,representative_key_mode,representative_key_shift,song_tier,representative_recording_id,lifecycle_state,deleted_at"),
        RECORDING("recording", "song_id,title_snapshot,artist_snapshot,version_code,key_mode,key_shift,tier,note,metadata_state,lifecycle_state,link_revision,condition_code,condition_name_snapshot,deleted_at"),
        PLAYLIST("playlist", "name,deleted_at"),
        TAG("tag", "name,archived_at"),
        CONDITION("condition_definition", "code,name,archived_at");
        private final String table, columns;
        Resource(String table, String columns) {this.table=table;this.columns=columns;}
    }
    private final JdbcTemplate jdbc;
    private final AccountAccess access;
    private final TransactionTemplate joined;
    private final Clock clock;
    public RevisionChanges(JdbcTemplate jdbc, AccountAccess access, PlatformTransactionManager manager, Clock clock) {
        this.jdbc=jdbc;this.access=access;this.clock=clock;
        joined=new TransactionTemplate(manager);
        joined.setPropagationBehavior(TransactionDefinition.PROPAGATION_MANDATORY);
    }

    /** Callback edits fields/relations only; this service alone increments the aggregate revision. */
    public Map<String,Object> change(AccountAccess.Account account, Resource resource, String id,
            Long baseRevision, Consumer<Map<String,Object>> edit) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()
                || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))
            throw new IllegalStateException("Revision change requires the mutation database transaction");
        return joined.execute(status -> {
            var owner=access.revalidate(account);
            UUID resourceId=parseId(id);
            if(baseRevision==null || baseRevision<1)throw invalid();
            Objects.requireNonNull(resource);Objects.requireNonNull(edit);
            var current=read(resource,owner.userId(),resourceId);
            long revision=((Number)current.get("revision")).longValue();
            if(revision!=baseRevision)throw new ApiException(HttpStatus.CONFLICT,"REVISION_CONFLICT",
                    "최신 값을 확인해 주세요.",false,Map.of("current_revision",revision,"current",current));
            if(revision==Long.MAX_VALUE)throw new ApiException(HttpStatus.CONFLICT,"REVISION_LIMIT_REACHED",
                    "더 이상 버전을 증가시킬 수 없습니다.",false,Map.of());
            var retentionBefore=new LinkedHashMap<>(current);
            edit.accept(current);
            var now=LocalDateTime.ofInstant(clock.instant(),ZoneOffset.UTC).truncatedTo(ChronoUnit.MILLIS);
            int updated=jdbc.update("UPDATE "+resource.table+" SET revision=revision+1,updated_at=? WHERE user_id=? AND id=? AND revision=?",
                    now,bytes(owner.userId()),bytes(resourceId),revision);
            if(updated!=1)throw new IllegalStateException("Edit changed the aggregate revision, identity or owner");
            var result=read(resource,owner.userId(),resourceId);
            com.ksh321.songrecord.api.retention.RetentionEvents.capture(owner.userId(),resource.name(),retentionBefore,result);
            return result;
        });
    }
    /** Pre-lock related aggregates in sorted order before locking the recording being moved. */
    public Map<String,Object> lock(AccountAccess.Account account,Resource resource,String id){
        if(!TransactionSynchronizationManager.isActualTransactionActive()
                || !TransactionSynchronizationManager.hasResource(Objects.requireNonNull(jdbc.getDataSource())))
            throw new IllegalStateException("Aggregate lock requires the mutation database transaction");
        return joined.execute(status->read(Objects.requireNonNull(resource),access.revalidate(account).userId(),parseId(id)));
    }
    private Map<String,Object> read(Resource resource,UUID owner,UUID id) {
        LockOrder.before(LockOrder.Rank.AGGREGATE,owner+"/"+resource.ordinal()+"/"+id);
        var rows=jdbc.query("SELECT id,revision,updated_at,"+resource.columns+" FROM "+resource.table+" WHERE user_id=? AND id=? FOR UPDATE",
                (rs,row)->snapshot(rs),bytes(owner),bytes(id));
        if(rows.isEmpty())throw notFound();
        return rows.getFirst();
    }
    private static Map<String,Object> snapshot(ResultSet rs) throws SQLException {
        var result=new LinkedHashMap<String,Object>();
        var metadata=rs.getMetaData();
        for(int i=1;i<=metadata.getColumnCount();i++) {
            String name=metadata.getColumnLabel(i).toLowerCase(Locale.ROOT);
            Object value=rs.getObject(i);
            if(value instanceof byte[] data) {
                var buffer=ByteBuffer.wrap(data);
                value=new UUID(buffer.getLong(),buffer.getLong()).toString();
            } else if(value instanceof Timestamp timestamp) {
                value=timestamp.toLocalDateTime().toInstant(ZoneOffset.UTC).toString();
            } else if(value instanceof LocalDateTime time) {
                value=time.toInstant(ZoneOffset.UTC).toString();
            }
            result.put(name,value);
        }
        return Collections.unmodifiableMap(result); // Preserve explicit nulls in the current state.
    }
    private static UUID parseId(String value) {
        try {var id=UUID.fromString(value);if(!id.toString().equals(value))throw notFound();return id;}
        catch(IllegalArgumentException | NullPointerException e){throw notFound();}
    }
    private static byte[] bytes(UUID id) {return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();}
    private static ApiException notFound(){return new ApiException(HttpStatus.NOT_FOUND,"RESOURCE_NOT_FOUND","요청한 자료를 찾을 수 없습니다.",false,Map.of());}
    private static ApiException invalid(){return new ApiException(HttpStatus.BAD_REQUEST,"VALIDATION_FAILED","base_revision을 확인해 주세요.",false,Map.of());}
}
