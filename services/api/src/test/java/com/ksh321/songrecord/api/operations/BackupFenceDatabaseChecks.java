package com.ksh321.songrecord.api.operations;
import java.time.Clock;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import com.ksh321.songrecord.api.storage.StorageObjectKeys;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
/** Shared H2 and migrated MySQL checks, only fresh synthetic subjects. */
public final class BackupFenceDatabaseChecks {
 public static void verify(JdbcTemplate db){
  var key=new StorageObjectKeys.Final(UUID.randomUUID(),UUID.randomUUID(),UUID.randomUUID());var fence=new BackupDeletionFence(db,Clock.systemUTC(),true);
  assertThatThrownBy(()->fence.generation(key)).isInstanceOf(BackupDeletionFence.Awaiting.class);
  assertThat(db.queryForObject("SELECT COUNT(*) FROM operational_backup_fence WHERE user_id=?",Long.class,bytes(key.owner()))).isEqualTo(1);
  db.update("UPDATE operational_backup_fence SET backup_ack_revision=revision WHERE user_id=?",bytes(key.owner()));fence.generation(key);
  fence.cancel(key);assertThatThrownBy(()->fence.generation(key)).isInstanceOf(BackupDeletionFence.Awaiting.class);
  assertThatThrownBy(()->fence.generation(key)).isInstanceOf(BackupDeletionFence.Awaiting.class);
  db.update("UPDATE operational_backup_fence SET backup_ack_revision=revision WHERE user_id=?",bytes(key.owner()));fence.generation(key);
  fence.committed(key);fence.cancel(key);
  assertThat(db.queryForObject("SELECT state FROM operational_backup_fence WHERE user_id=?",String.class,bytes(key.owner()))).isEqualTo("COMMITTED");
  assertThat(fence.ownerBackupsAbsent(key.owner())).isFalse();
  assertThatThrownBy(()->fence.authorize(key.owner(),"USER",UUID.randomUUID(),null)).isInstanceOf(IllegalArgumentException.class);
  assertThatThrownBy(()->fence.authorize(key.owner(),"USER",key.owner(),null)).isInstanceOf(BackupDeletionFence.Awaiting.class);
  db.update("UPDATE operational_backup_fence SET backup_ack_revision=revision,backup_absent_at=CURRENT_TIMESTAMP WHERE user_id=? AND entity_type='USER'",bytes(key.owner()));
  assertThat(fence.ownerBackupsAbsent(key.owner())).isTrue();
 }
}
