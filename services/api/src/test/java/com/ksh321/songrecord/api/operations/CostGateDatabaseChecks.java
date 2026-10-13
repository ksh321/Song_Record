package com.ksh321.songrecord.api.operations;
import java.time.*;
import java.sql.Timestamp;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static org.assertj.core.api.Assertions.*;
public final class CostGateDatabaseChecks {
 public static void verify(JdbcTemplate db) {
  var manager=new DataSourceTransactionManager(db.getDataSource());var now=Instant.parse("2026-10-13T00:00:00Z");
  db.update("UPDATE global_storage_usage SET cost_monitor_required=TRUE,upload_locked=TRUE,reconciliation_locked=TRUE WHERE id=1");
  CostGate.observe(db,manager,now,now,70000);
  assertThat(CostGate.blocks(db.queryForMap("SELECT * FROM global_storage_usage WHERE id=1"),now)).isTrue();
  assertThatThrownBy(()->CostGate.observe(db,manager,now,now.minusSeconds(1),0)).isInstanceOf(IllegalArgumentException.class);
  CostGate.observe(db,manager,now.plusSeconds(1),now.plusSeconds(1),49999);
  var row=db.queryForMap("SELECT * FROM global_storage_usage WHERE id=1");
  assertThat(CostGate.blocks(row,now.plusSeconds(1))).isFalse();
  assertThat(CostGate.blocks(row,now.plus(Duration.ofHours(27)))).isTrue();
  assertThat(((Number)row.get("cost_monthly_estimate_krw")).longValue()).isEqualTo(49999);
  assertThat(db.queryForObject("SELECT upload_locked FROM global_storage_usage WHERE id=1",Boolean.class)).isTrue();
  assertThat(db.queryForObject("SELECT reconciliation_locked FROM global_storage_usage WHERE id=1",Boolean.class)).isTrue();
  assertThatThrownBy(()->CostGate.observe(db,manager,now,now.plusSeconds(301),0)).isInstanceOf(IllegalArgumentException.class);
 }
}
