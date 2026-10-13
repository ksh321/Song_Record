package com.ksh321.songrecord.api.operations;
import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.HashMap;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import static org.assertj.core.api.Assertions.*;
class CostGateTests {
 @Test void unknownRequiredMeterClosesOnlyItsOwnGate() {
  var row=new HashMap<String,Object>();row.put("cost_monitor_required",true);row.put("cost_upload_locked",false);
  assertThat(CostGate.blocks(row,Instant.now())).isTrue();row.put("cost_monitor_required",false);assertThat(CostGate.blocks(row,Instant.now())).isFalse();
 }
 @Test void observationsCannotClearOtherLocksOrReplayOldZeroCost() {
  var db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:cost_"+java.util.UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
  db.execute("CREATE TABLE global_storage_usage(id INT PRIMARY KEY,cost_monitor_required BOOLEAN,cost_upload_locked BOOLEAN,cost_observed_at TIMESTAMP(3),cost_monthly_estimate_krw BIGINT,upload_locked BOOLEAN,reconciliation_locked BOOLEAN,revision BIGINT DEFAULT 1)");db.update("INSERT INTO global_storage_usage(id) VALUES(1)");CostGateDatabaseChecks.verify(db);
 }
}
