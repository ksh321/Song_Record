package com.ksh321.songrecord.api.retention;
import com.ksh321.songrecord.api.uploads.*;import java.time.*;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;import static org.assertj.core.api.Assertions.*;
public final class UploadRecoveryDatabaseChecks {
 public static void verify(JdbcTemplate db){
  var f=UploadFinalizationDatabaseChecks.fixture(db);var recovery=new UploadRecovery(db,new DataSourceTransactionManager(db.getDataSource()),f.clock());
  assertThat(recovery.cancel(f.owner(),f.attempt())).isEqualTo("CANCELLED");assertThat(recovery.cancel(f.owner(),f.attempt())).isEqualTo("CANCELLED");
  assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isZero();
  assertThat(db.queryForObject("SELECT used_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(f.owner()))).isZero();
  assertThat(f.jobs().complete(f.lease(),()->{throw new AssertionError("old lease ran");})).isFalse();
  var exp=UploadFinalizationDatabaseChecks.fixture(db);var expiry=new UploadRecovery(db,new DataSourceTransactionManager(db.getDataSource()),exp.clock());
  exp.clock().now=exp.clock().now.plus(Duration.ofHours(24));assertThat(expiry.expire()).isEqualTo(1);assertThat(expiry.expire()).isZero();
  assertThat(db.queryForObject("SELECT reserved_bytes FROM storage_usage WHERE user_id=?",Long.class,bytes(exp.owner()))).isZero();
  assertThat(db.queryForObject("SELECT state FROM recording_upload WHERE id=?",String.class,bytes(exp.attempt()))).isEqualTo("EXPIRED");
  // A live worker is fenced first, never racing an expiry release.
  var live=UploadFinalizationDatabaseChecks.fixture(db);db.update("UPDATE recording_upload SET expires_at=? WHERE id=?",java.sql.Timestamp.from(live.clock().instant().plusSeconds(1)),bytes(live.attempt()));live.clock().now=live.clock().now.plusSeconds(2);
  assertThat(new UploadRecovery(db,new DataSourceTransactionManager(db.getDataSource()),live.clock()).expire()).isZero();
 }
}
