package com.ksh321.songrecord.api.operations;
import java.time.*;
import java.sql.Timestamp;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
/** Aggregate-only operator projection. Never selects payloads, notes, object keys, URLs or tokens. */
public final class OperationsMetrics {
 public static Map<String,Object> demand(JdbcTemplate db,Instant now){
  var start=Timestamp.from(now.minus(Duration.ofDays(30)));var end=Timestamp.from(now);
  var row=new LinkedHashMap<String,Object>();
  row.put("window_start_utc",start.toInstant().toString());row.put("window_end_utc",now.toString());
  row.put("server_observed_active_accounts",db.queryForObject("SELECT COUNT(DISTINCT actor_id) FROM operations_observation WHERE actor_kind='USER' AND action IN ('SONG_READ','RECORDING_SAVED') AND result='SUCCESS' AND observed_at>=? AND observed_at<=?",Long.class,start,end));
  row.put("pin_limit_accounts",db.queryForObject("SELECT COUNT(DISTINCT actor_id) FROM operations_observation WHERE actor_kind='USER' AND result='PIN_LIMIT_REACHED' AND observed_at>=? AND observed_at<=?",Long.class,start,end));
  row.put("quota_accounts",db.queryForObject("SELECT COUNT(DISTINCT actor_id) FROM operations_observation WHERE actor_kind='USER' AND result='QUOTA_EXCEEDED' AND observed_at>=? AND observed_at<=?",Long.class,start,end));
  row.put("server_observed_active_pin_ten_accounts",db.queryForObject("SELECT COUNT(DISTINCT p.actor_id) FROM operations_observation p WHERE p.action='PIN_SLOTS_TEN' AND p.observed_at>=? AND p.observed_at<=? AND EXISTS(SELECT 1 FROM operations_observation a WHERE a.actor_id=p.actor_id AND a.actor_kind='USER' AND a.action IN ('SONG_READ','RECORDING_SAVED') AND a.result='SUCCESS' AND a.observed_at>=? AND a.observed_at<=?)",Long.class,start,end,start,end));
  row.put("second_recording_save_accounts",db.queryForObject("SELECT COUNT(*) FROM (SELECT actor_id FROM operations_observation WHERE actor_kind='USER' AND action='RECORDING_SAVED' AND result='SUCCESS' AND target_id IS NOT NULL AND observed_at>=? AND observed_at<=? GROUP BY actor_id HAVING COUNT(DISTINCT target_id)>=2) observed",Long.class,start,end));
  row.put("actual_playback_accounts",null);row.put("client_offline_coverage","NOT_CONNECTED: playback URL issuance is not actual playback; offline activity is not observed by this server projection");
  return row;
 }
 public static Map<String,Object> snapshot(JdbcTemplate db,Instant now){
  var row=new LinkedHashMap<String,Object>();row.put("observed_utc",now.toString());row.put("demand",demand(db,now));
  row.put("http_by_action",db.queryForList("SELECT action,result,COUNT(*) AS event_count,MAX(duration_ms) AS max_duration_ms,AVG(duration_ms) AS mean_duration_ms,MAX(sync_change_backlog) AS max_sync_change_backlog FROM operations_observation WHERE actor_kind<>'WORKER' AND observed_at>=? GROUP BY action,result",Timestamp.from(now.minus(Duration.ofHours(24)))));
  row.put("queue",db.queryForList("SELECT type,state,COUNT(*) AS job_count,MAX(attempt_count) AS max_attempts,MIN(run_after) AS oldest_due_at FROM job GROUP BY type,state"));
  row.put("expired_leases",db.queryForObject("SELECT COUNT(*) FROM job WHERE state='RUNNING' AND lease_until<=?",Long.class,Timestamp.from(now)));
  row.put("capacity",db.queryForMap("SELECT used_bytes,reserved_bytes,primary_quota_bytes,temp_observed_bytes,final_observed_bytes,reconciliation_issue_count,reconciliation_at,upload_locked,reconciliation_locked,cost_upload_locked,cost_observed_at FROM global_storage_usage WHERE id=1"));
  row.put("pin_storage_separate",db.queryForMap("SELECT COALESCE(SUM(CASE WHEN current_recording_id IS NOT NULL THEN 1 ELSE 0 END),0) AS occupied_current,COALESCE(SUM(CASE WHEN pending_recording_id IS NOT NULL THEN 1 ELSE 0 END),0) AS pending_slots FROM pin_slot"));
  row.put("storage_requests_30d",db.queryForMap("SELECT COUNT(*) AS submitted_requests,COUNT(DISTINCT user_id) AS submitting_accounts FROM storage_request_ledger WHERE received_at>=? AND received_at<=?",Timestamp.from(now.minus(Duration.ofDays(30))),Timestamp.from(now)));
  row.put("chart_freshness",db.queryForList("SELECT brand,period,state,COUNT(*) AS snapshot_count,MAX(fetched_at) AS latest_fetched_at,MAX(published_at) AS latest_published_at FROM chart_snapshot GROUP BY brand,period,state"));
  row.put("deletion_audit",db.queryForList("SELECT entity_type,COUNT(*) AS ledger_count,MAX(purged_at) AS latest_purged_at FROM deletion_ledger GROUP BY entity_type"));
  row.put("account_deletion",db.queryForMap("SELECT COUNT(*) AS pending_count,MAX(failure_count) AS max_failures,MIN(accepted_at) AS oldest_accepted_at FROM account_deletion_work WHERE backup_confirmed_at IS NULL"));
  row.put("scope","Server observations only; no client playback/offline claims; null freshness means unobserved, not healthy. Audit actor/target UUIDs remain private DB rows.");
  return row;
 }
}
