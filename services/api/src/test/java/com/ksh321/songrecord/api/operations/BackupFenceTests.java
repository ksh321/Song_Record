package com.ksh321.songrecord.api.operations;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
public class BackupFenceTests {
 @Test void mysqlDatetimeAndTimestampProjectToSameUtcMetadata(){
  var instant=java.time.Instant.parse("2026-10-14T01:00:00Z");var owner=java.util.UUID.randomUUID();var entity=java.util.UUID.randomUUID();
  var row=new java.util.HashMap<String,Object>();row.put("user_id",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(owner));row.put("entity_id",com.ksh321.songrecord.api.songs.SongQueryKeys.bytes(entity));row.put("entity_type","RECORDING");row.put("revision",1L);
  row.put("purged_at",java.sql.Timestamp.from(instant));var first=BackupLedgerOperator.project(row,"purged_at");
  row.put("purged_at",java.time.LocalDateTime.ofInstant(instant,java.time.ZoneOffset.UTC));var second=BackupLedgerOperator.project(row,"purged_at");
  org.assertj.core.api.Assertions.assertThat(first).isEqualTo(second);org.assertj.core.api.Assertions.assertThat(second.get("at")).isEqualTo(instant.toString());
 }
 @Test void confirmedRemoteRevisionGatesDeletionAndCancelledCopyCanRetry(){
  var db=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:backup"+java.util.UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
  db.execute("CREATE TABLE operational_backup_fence(id BINARY(16) PRIMARY KEY,user_id BINARY(16),entity_type VARCHAR(32),entity_id BINARY(16),object_generation BINARY(16),generation_key BINARY(16) GENERATED ALWAYS AS(COALESCE(object_generation,X'00000000000000000000000000000000')),state VARCHAR(16) DEFAULT 'REQUESTED',revision BIGINT DEFAULT 1,backup_ack_revision BIGINT DEFAULT 0,requested_at TIMESTAMP,updated_at TIMESTAMP,backup_absent_at TIMESTAMP,UNIQUE(user_id,entity_type,entity_id,generation_key))");
  BackupFenceDatabaseChecks.verify(db);
 }
}
