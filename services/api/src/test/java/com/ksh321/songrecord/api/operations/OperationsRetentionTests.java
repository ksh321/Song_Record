package com.ksh321.songrecord.api.operations;

import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class OperationsRetentionTests {
 JdbcTemplate db;DataSourceTransactionManager manager;
 @BeforeEach void open(){var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");db=new JdbcTemplate(ds);manager=new DataSourceTransactionManager(ds);db.execute("CREATE TABLE operations_observation(id BINARY(16) PRIMARY KEY,actor_kind VARCHAR(16),action VARCHAR(32),result VARCHAR(32),status_code INT,duration_ms BIGINT,observed_at TIMESTAMP(3))");}
 @AfterEach void close(){db.execute("SHUTDOWN");}
 @Test void boundedExpiryKeepsBoundaryAndRecentRows(){OperationsRetentionDatabaseChecks.verify(db);}
 @Test void aDeleteFailureRollsBackEarlierRowsInTheSameBatch(){
  var now=Instant.parse("2026-10-15T00:00:00Z");var first=UUID.randomUUID();var blocked=UUID.randomUUID();
  OperationsRetentionDatabaseChecks.insert(db,first,now.minus(Duration.ofDays(32)));OperationsRetentionDatabaseChecks.insert(db,blocked,now.minus(Duration.ofDays(31)));
  db.execute("CREATE TABLE synthetic_reference(id INT PRIMARY KEY,observation_id BINARY(16),FOREIGN KEY(observation_id) REFERENCES operations_observation(id))");db.update("INSERT INTO synthetic_reference VALUES(1,?)",bytes(blocked));
  assertThatThrownBy(()->new OperationsRetention(db,manager,500).prune(now)).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operations_observation",Long.class)).isEqualTo(2);
 }
 @Test void apiRoleCannotActivateRetention(){assertThatThrownBy(()->new OperationsRetentionConfiguration().operationsRetention(db,manager,"api")).isInstanceOf(IllegalArgumentException.class);}
}
