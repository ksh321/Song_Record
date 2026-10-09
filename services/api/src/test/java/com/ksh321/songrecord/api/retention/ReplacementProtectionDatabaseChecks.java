package com.ksh321.songrecord.api.retention;
import java.util.*;import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;import static org.assertj.core.api.Assertions.*;
public final class ReplacementProtectionDatabaseChecks {
 public static void verify(JdbcTemplate db){
  UUID owner=account(db),dev=device(db,owner),song=song(db,owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
  UUID old=recording(db,owner,dev,song,true,true,"VALIDATED");db.update("UPDATE recording SET recorded_at='2026-01-01 00:00:00' WHERE id=?",bytes(old));stored(db,owner,old);
  var store=new RetentionSelectionStore(db,new DataSourceTransactionManager(db.getDataSource()));var initial=store.recalculate(owner,song).orElseThrow();assertThat(initial.ids().latest()).isEqualTo(old);var before=db.queryForMap("SELECT object_key,generation,verified_size,sha256 FROM recording_asset WHERE recording_id=?",bytes(old));
  UUID newer=recording(db,owner,dev,song,true,true,"VALIDATED");db.update("UPDATE recording SET recorded_at='2026-01-02 00:00:00' WHERE id=?",bytes(newer));var next=store.recalculate(owner,song).orElseThrow();assertThat(next.ids().latest()).isEqualTo(newer);
  assertThat(holds(db,owner,old)).isEqualTo(1);assertThat(db.queryForObject("SELECT required_selection_revision FROM cloud_hold WHERE user_id=?",Long.class,bytes(owner))).isEqualTo(next.revision());long revision=db.queryForObject("SELECT cloud_revision FROM recording_asset WHERE recording_id=?",Long.class,bytes(old));
  assertThat(store.recalculate(owner,song)).contains(next);assertThat(holds(db,owner,old)).isEqualTo(1);assertThat(db.queryForObject("SELECT cloud_revision FROM recording_asset WHERE recording_id=?",Long.class,bytes(old))).isEqualTo(revision);
  // A newer replacement supersedes the waiting target; completing the obsolete target is insufficient.
  UUID newest=recording(db,owner,dev,song,true,true,"VALIDATED");db.update("UPDATE recording SET recorded_at='2026-01-03 00:00:00' WHERE id=?",bytes(newest));var latest=store.recalculate(owner,song).orElseThrow();assertThat(holds(db,owner,old)).isEqualTo(1);stored(db,owner,newer);store.recalculate(owner,song);assertThat(holds(db,owner,old)).isEqualTo(1);
  stored(db,owner,newest);store.refreshReplacementHolds();assertThat(holds(db,owner,old)).isZero();assertThat(db.queryForMap("SELECT object_key,generation,verified_size,sha256 FROM recording_asset WHERE recording_id=?",bytes(old))).usingRecursiveComparison().isEqualTo(before);assertThat(db.queryForObject("SELECT cloud_state FROM recording_asset WHERE recording_id=?",String.class,bytes(old))).isEqualTo("STORED");assertThat(store.recalculate(owner,song)).contains(latest);
  // Role withdrawal can release this reason; it still never deletes the prior server object.
  UUID last=recording(db,owner,dev,song,true,true,"VALIDATED");db.update("UPDATE recording SET recorded_at='2026-01-04 00:00:00' WHERE id=?",bytes(last));store.recalculate(owner,song);assertThat(holds(db,owner,newest)).isEqualTo(1);
  db.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(song));store.recalculate(owner,song);assertThat(db.queryForObject("SELECT COUNT(*) FROM cloud_hold WHERE user_id=?",Long.class,bytes(owner))).isZero();assertThat(db.queryForObject("SELECT COUNT(*) FROM recording_asset WHERE user_id=? AND cloud_state='STORED'",Long.class,bytes(owner))).isEqualTo(3);
  assertThat(store.recalculate(UUID.randomUUID(),song)).isEmpty();
 }
 private static long holds(JdbcTemplate db,UUID owner,UUID recording){return db.queryForObject("SELECT COUNT(*) FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason='PENDING_REPLACEMENT'",Long.class,bytes(owner),bytes(recording));}
 private static void stored(JdbcTemplate db,UUID owner,UUID id){var generation=UUID.randomUUID();db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at,cloud_revision) VALUES(?,?,'STORED',?,?,6291456,?,CURRENT_TIMESTAMP,1)",bytes(id),bytes(owner),new com.ksh321.songrecord.api.storage.StorageObjectKeys.Final(owner,id,generation).value(),bytes(generation),"a".repeat(64));}
}
