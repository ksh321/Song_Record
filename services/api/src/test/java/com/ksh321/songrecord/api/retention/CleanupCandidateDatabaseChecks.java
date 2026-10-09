package com.ksh321.songrecord.api.retention;
import java.util.*;import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import static com.ksh321.songrecord.api.retention.RetentionCandidateDatabaseChecks.*;import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;import static org.assertj.core.api.Assertions.*;
public final class CleanupCandidateDatabaseChecks {
 public static void verify(JdbcTemplate db){
  UUID owner=account(db),dev=device(db,owner),song=song(db,owner);db.update("INSERT INTO user_sync_state(user_id) VALUES(?)",bytes(owner));
  UUID a=recording(db,owner,dev,song,true,true,"VALIDATED");stored(db,owner,a);var service=new CleanupCandidates(db,new DataSourceTransactionManager(db.getDataSource()));
  assertThat(service.recalculate(owner,a)).isFalse();assertThat(holds(db,owner,a,"WAITING_LOCAL_CONFIRM")).isZero();
  // Fresh metadata is authoritative even before an asynchronous selection job catches up.
  db.update("UPDATE song SET lifecycle_state='TRASHED',deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(song));
  var asset=db.queryForMap("SELECT object_key,generation,sha256,verified_size,cloud_state FROM recording_asset WHERE recording_id=?",bytes(a));
  assertThat(service.recalculate(owner,a)).isTrue();assertThat(holds(db,owner,a,"WAITING_LOCAL_CONFIRM")).isEqualTo(1);long revision=db.queryForObject("SELECT cloud_revision FROM recording_asset WHERE recording_id=?",Long.class,bytes(a));
  service.refresh();service.recalculate(owner,a);assertThat(holds(db,owner,a,"WAITING_LOCAL_CONFIRM")).isEqualTo(1);assertThat(db.queryForObject("SELECT cloud_revision FROM recording_asset WHERE recording_id=?",Long.class,bytes(a))).isEqualTo(revision);
  db.update("INSERT INTO user_entitlement(user_id,quota_bytes,pinned_limit,revision) VALUES(?,1000000000,10,1)",bytes(owner));
  db.update("INSERT INTO pin_slot(user_id,slot_no,current_recording_id,revision,operation_id,requested_at) VALUES(?,1,?,1,?,CURRENT_TIMESTAMP)",bytes(owner),bytes(a),bytes(UUID.randomUUID()));
  assertThat(service.recalculate(owner,a)).isFalse();assertThat(holds(db,owner,a,"WAITING_LOCAL_CONFIRM")).isZero();
  db.update("UPDATE pin_slot SET pending_recording_id=current_recording_id,current_recording_id=NULL WHERE user_id=?",bytes(owner));
  assertThat(service.recalculate(owner,a)).isFalse();assertThat(holds(db,owner,a,"WAITING_LOCAL_CONFIRM")).isZero();
  db.update("DELETE FROM pin_slot WHERE user_id=?",bytes(owner));
  db.update("INSERT INTO cloud_hold(id,user_id,recording_id,reason,related_operation_id,required_selection_revision) VALUES(?,?,?,'PENDING_REPLACEMENT',?,1)",bytes(UUID.randomUUID()),bytes(owner),bytes(a),bytes(song));
  assertThat(service.recalculate(owner,a)).isFalse();assertThat(holds(db,owner,a,"PENDING_REPLACEMENT")).isEqualTo(1);
  db.update("DELETE FROM cloud_hold WHERE user_id=?",bytes(owner));db.update("UPDATE recording SET song_id=NULL WHERE id=?",bytes(a));
  assertThat(service.recalculate(owner,a)).isFalse();assertThat(holds(db,owner,a,"ORPHAN_KEEP")).isEqualTo(1);assertThat(db.queryForObject("SELECT COUNT(*) FROM pin_slot WHERE user_id=?",Long.class,bytes(owner))).isZero();
  assertThat(service.recalculate(UUID.randomUUID(),a)).isFalse();db.update("UPDATE app_user SET status='DELETING' WHERE id=?",bytes(owner));assertThat(service.recalculate(owner,a)).isFalse();
  assertThat(db.queryForMap("SELECT object_key,generation,sha256,verified_size,cloud_state FROM recording_asset WHERE recording_id=?",bytes(a))).usingRecursiveComparison().isEqualTo(asset);
 }
 private static long holds(JdbcTemplate db,UUID owner,UUID recording,String reason){return db.queryForObject("SELECT COUNT(*) FROM cloud_hold WHERE user_id=? AND recording_id=? AND reason=?",Long.class,bytes(owner),bytes(recording),reason);}
 private static void stored(JdbcTemplate db,UUID owner,UUID id){var generation=UUID.randomUUID();db.update("INSERT INTO recording_asset(recording_id,user_id,cloud_state,object_key,generation,verified_size,sha256,stored_at,cloud_revision) VALUES(?,?,'STORED',?,?,6291456,?,CURRENT_TIMESTAMP,1)",bytes(id),bytes(owner),new com.ksh321.songrecord.api.storage.StorageObjectKeys.Final(owner,id,generation).value(),bytes(generation),"a".repeat(64));}
}
