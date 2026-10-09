package com.ksh321.songrecord.api.retention;
import org.junit.jupiter.api.Test;
class UploadFinalizationTests {
 @Test void immutableBytesAndAtomicFencedAccounting()throws Exception{var db=UploadApprovalTests.database();try(var c=db.getDataSource().getConnection()){new org.springframework.jdbc.datasource.init.ResourceDatabasePopulator(new org.springframework.core.io.ClassPathResource("job-schema.sql")).populate(c);UploadFinalizationDatabaseChecks.verify(db);}}
 @Test void mysqlDatetimeAndH2TimestampRepresentSameUtcExpiry(){var expected=java.time.Instant.parse("2026-10-09T12:00:00Z");org.assertj.core.api.Assertions.assertThat(com.ksh321.songrecord.api.uploads.UploadFinalization.instant(java.time.LocalDateTime.ofInstant(expected,java.time.ZoneOffset.UTC))).isEqualTo(expected);org.assertj.core.api.Assertions.assertThat(com.ksh321.songrecord.api.uploads.UploadFinalization.instant(java.sql.Timestamp.from(expected))).isEqualTo(expected);}
}
