package com.ksh321.songrecord.api.operations;

import java.time.*;
import java.sql.Timestamp;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Only the cost-owned gate is updated. Manual and reconciliation gates retain their owners. */
public final class CostGate {
    public static boolean blocks(Map<String,Object> row, Instant now) {
        if (!flag(row.get("cost_monitor_required"))) return false;
        Object date = row.get("cost_observed_at");
        Instant observed = date instanceof Timestamp t ? t.toInstant()
            : date instanceof LocalDateTime t ? t.toInstant(ZoneOffset.UTC) : null;
        return flag(row.get("cost_upload_locked")) || observed == null
            || observed.isAfter(now.plusSeconds(300)) || observed.isBefore(now.minus(Duration.ofHours(26)));
    }
    private static boolean flag(Object value) { return Boolean.TRUE.equals(value) || value instanceof Number n && n.intValue()!=0; }
    public static void observe(JdbcTemplate db, PlatformTransactionManager manager, Instant now, Instant observed, long krw) {
        if (krw < 0 || observed.isAfter(now.plusSeconds(300)) || observed.isBefore(now.minus(Duration.ofHours(26))))
            throw new IllegalArgumentException("COST_OBSERVATION_INVALID");
        new TransactionTemplate(manager).executeWithoutResult(status -> {
            var row=db.queryForMap("SELECT cost_observed_at FROM global_storage_usage WHERE id=1 FOR UPDATE");
            Object previous=row.get("cost_observed_at");
            Instant at=previous instanceof Timestamp t?t.toInstant():previous instanceof LocalDateTime t?t.toInstant(ZoneOffset.UTC):null;
            if(at!=null && !observed.isAfter(at))throw new IllegalArgumentException("COST_OBSERVATION_NOT_NEWER");
            if(db.update("UPDATE global_storage_usage SET cost_upload_locked=?,cost_observed_at=?,cost_monthly_estimate_krw=?,revision=revision+1 WHERE id=1",krw>=70000,Timestamp.from(observed),krw)!=1)
                throw new IllegalStateException("COST_GATE_MISSING");
        });
    }
}
