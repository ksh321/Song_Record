#!/usr/bin/env bash
set -euo pipefail

verification_log="$(mktemp)"
trap 'rm -f "$verification_log"' EXIT

run_sql() {
  docker compose exec -T mysql sh -lc \
    'MYSQL_PWD="$MYSQL_PASSWORD" mysql --protocol=tcp -h127.0.0.1 -u"$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names' \
    <<<"$1"
}

expect_rejected() {
  local label="$1"
  local statement="$2"
  if run_sql "$statement" >"$verification_log" 2>&1; then
    echo "Expected rejection but SQL succeeded: $label"
    exit 1
  fi
  echo "Rejected as expected: $label"
}

expect_value() {
  local label="$1"
  local statement="$2"
  local expected="$3"
  local actual
  actual="$(run_sql "$statement")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected value for $label: expected '$expected', got '$actual'"
    exit 1
  fi
  echo "Verified: $label"
}

expect_value \
  "incremental migration kept the V1 row" \
  "SELECT schema_value FROM app_schema_metadata WHERE schema_key='upgrade_sentinel';" \
  "kept"
expect_value \
  "Flyway applied V1 and V2" \
  "SELECT GROUP_CONCAT(version ORDER BY installed_rank SEPARATOR ',') FROM flyway_schema_history WHERE success=1;" \
  "1,2"
expect_value \
  "schema contract moved to version 2" \
  "SELECT schema_value FROM app_schema_metadata WHERE schema_key='schema_contract';" \
  "2"

run_sql "
INSERT INTO app_user (id) VALUES
  (UUID_TO_BIN('10000000-0000-4000-8000-000000000001')),
  (UUID_TO_BIN('10000000-0000-4000-8000-000000000002'));
INSERT INTO user_entitlement (user_id) VALUES
  (UUID_TO_BIN('10000000-0000-4000-8000-000000000001')),
  (UUID_TO_BIN('10000000-0000-4000-8000-000000000002'));
INSERT INTO device (id, user_id, display_name, last_seen_at) VALUES
  (UUID_TO_BIN('20000000-0000-4000-8000-000000000001'), UUID_TO_BIN('10000000-0000-4000-8000-000000000001'), 'device one', UTC_TIMESTAMP(3));
INSERT INTO auth_identity (id, user_id, provider, provider_user_id, email) VALUES
  (UUID_TO_BIN('21000000-0000-4000-8000-000000000001'), UUID_TO_BIN('10000000-0000-4000-8000-000000000001'), 'GOOGLE', 'google-user-1', 'same@example.com'),
  (UUID_TO_BIN('21000000-0000-4000-8000-000000000002'), UUID_TO_BIN('10000000-0000-4000-8000-000000000002'), 'KAKAO', 'kakao-user-2', 'same@example.com');
"

expect_rejected \
  "same provider user id cannot belong to another user" \
  "INSERT INTO auth_identity (id,user_id,provider,provider_user_id,email) VALUES (UUID_TO_BIN('21000000-0000-4000-8000-000000000003'),UUID_TO_BIN('10000000-0000-4000-8000-000000000002'),'GOOGLE','google-user-1','other@example.com');"
expect_rejected \
  "session cannot reference another owner's device" \
  "INSERT INTO auth_session (id,user_id,device_id,refresh_hash,expires_at) VALUES (UUID_TO_BIN('22000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000002'),UUID_TO_BIN('20000000-0000-4000-8000-000000000001'),UNHEX(REPEAT('a',64)),UTC_TIMESTAMP(3)+INTERVAL 1 DAY);"

run_sql "
INSERT INTO song (id,user_id,source_type,tj_number,title,artist,version_code,note) VALUES
  (UUID_TO_BIN('30000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'TJ','00123','첫 곡','가수','NORMAL',''),
  (UUID_TO_BIN('30000000-0000-4000-8000-000000000003'),UUID_TO_BIN('10000000-0000-4000-8000-000000000002'),'TJ','00123','다른 계정 곡','가수','NORMAL',''),
  (UUID_TO_BIN('30000000-0000-4000-8000-000000000004'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'MANUAL',NULL,'직접 등록','가수','LIVE','');
"

expect_rejected \
  "manual song cannot reserve a TJ number" \
  "INSERT INTO song (id,user_id,source_type,tj_number,title,artist,version_code,note) VALUES (UUID_TO_BIN('30000000-0000-4000-8000-000000000006'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'MANUAL','777','잘못된 곡','가수','NORMAL','');"
expect_rejected \
  "active and trashed lifecycles reserve TJ number per account" \
  "INSERT INTO song (id,user_id,source_type,tj_number,title,artist,version_code,note) VALUES (UUID_TO_BIN('30000000-0000-4000-8000-000000000002'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'TJ','00123','중복 곡','가수','NORMAL','');"

run_sql "
UPDATE song
   SET lifecycle_state='PURGED', deleted_at=UTC_TIMESTAMP(3)
 WHERE id=UUID_TO_BIN('30000000-0000-4000-8000-000000000001');
INSERT INTO song (id,user_id,source_type,tj_number,title,artist,version_code,note) VALUES
  (UUID_TO_BIN('30000000-0000-4000-8000-000000000005'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'TJ','00123','영구 삭제 후 재등록','가수','MR','');
INSERT INTO song_source (song_id,user_id,provider,source_title,source_artist,source_ref,verified_at) VALUES
  (UUID_TO_BIN('30000000-0000-4000-8000-000000000005'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'TJ','원본 곡명','원본 가수','00123',UTC_TIMESTAMP(3));
"

expect_rejected \
  "manual song cannot receive a TJ source row" \
  "INSERT INTO song_source (song_id,user_id,provider,source_title,source_artist,source_ref,verified_at) VALUES (UUID_TO_BIN('30000000-0000-4000-8000-000000000004'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'TJ','원본','가수','manual',UTC_TIMESTAMP(3));"

run_sql "
INSERT INTO recording (
  id,user_id,origin_device_id,song_id,title_snapshot,artist_snapshot,
  version_code,key_mode,key_shift,tier,note,recorded_at,timezone_id,
  timezone_offset_minutes,metadata_state
) VALUES
  (UUID_TO_BIN('40000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('20000000-0000-4000-8000-000000000001'),UUID_TO_BIN('30000000-0000-4000-8000-000000000005'),NULL,NULL,'NORMAL',NULL,NULL,NULL,'',UTC_TIMESTAMP(3),'Asia/Seoul',540,'DRAFT'),
  (UUID_TO_BIN('40000000-0000-4000-8000-000000000002'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('20000000-0000-4000-8000-000000000001'),UUID_TO_BIN('30000000-0000-4000-8000-000000000004'),NULL,NULL,'LIVE',NULL,NULL,NULL,'',UTC_TIMESTAMP(3),'Asia/Seoul',540,'DRAFT'),
  (UUID_TO_BIN('40000000-0000-4000-8000-000000000003'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('20000000-0000-4000-8000-000000000001'),NULL,NULL,NULL,'MR',NULL,NULL,NULL,'',UTC_TIMESTAMP(3),'Asia/Seoul',540,'DRAFT');
"

expect_rejected \
  "recording cannot reference another owner's song" \
  "INSERT INTO recording (id,user_id,origin_device_id,song_id,version_code,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state) VALUES (UUID_TO_BIN('40000000-0000-4000-8000-000000000004'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('20000000-0000-4000-8000-000000000001'),UUID_TO_BIN('30000000-0000-4000-8000-000000000003'),'NORMAL','',UTC_TIMESTAMP(3),'Asia/Seoul',540,'DRAFT');"
expect_rejected \
  "recording version is limited to NORMAL MR LIVE" \
  "INSERT INTO recording (id,user_id,origin_device_id,version_code,note,recorded_at,timezone_id,timezone_offset_minutes,metadata_state) VALUES (UUID_TO_BIN('40000000-0000-4000-8000-000000000005'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('20000000-0000-4000-8000-000000000001'),'UNKNOWN','',UTC_TIMESTAMP(3),'Asia/Seoul',540,'DRAFT');"
expect_rejected \
  "SAVED transition requires a file specification" \
  "UPDATE recording SET title_snapshot='녹음',artist_snapshot='가수',key_mode='ORIGINAL',key_shift=0,metadata_state='SAVED' WHERE id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');"

run_sql "
INSERT INTO recording_file_spec (
  recording_id,user_id,sha256,size_bytes,duration_ms,codec,sample_rate,channels,capture_integrity
) VALUES (
  UUID_TO_BIN('40000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),
  REPEAT('a',64),1048576,60000,'AAC_LC',48000,1,'VALIDATED'
);
UPDATE recording
   SET title_snapshot='녹음 당시 곡명',artist_snapshot='녹음 당시 가수',
       key_mode='ORIGINAL',key_shift=0,metadata_state='SAVED'
 WHERE id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');
UPDATE song
   SET representative_recording_id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001')
 WHERE id=UUID_TO_BIN('30000000-0000-4000-8000-000000000005');
"

expect_rejected \
  "SAVED file specification cannot change" \
  "UPDATE recording_file_spec SET size_bytes=1048577 WHERE recording_id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');"
expect_rejected \
  "SAVED file specification cannot be deleted" \
  "DELETE FROM recording_file_spec WHERE recording_id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');"
expect_rejected \
  "SAVED recording cannot return to DRAFT" \
  "UPDATE recording SET metadata_state='DRAFT' WHERE id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');"
expect_rejected \
  "representative recording must belong to the same song" \
  "UPDATE song SET representative_recording_id=UUID_TO_BIN('40000000-0000-4000-8000-000000000002') WHERE id=UUID_TO_BIN('30000000-0000-4000-8000-000000000005');"
expect_rejected \
  "STORED asset requires final object fields" \
  "INSERT INTO recording_asset (recording_id,user_id,cloud_state) VALUES (UUID_TO_BIN('40000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'STORED');"

run_sql "
INSERT INTO recording_asset (recording_id,user_id,cloud_state) VALUES
  (UUID_TO_BIN('40000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),'QUEUED');
INSERT INTO recording_upload (
  id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,
  temp_key,final_key,policy_revision,expires_at
) VALUES
  (UUID_TO_BIN('50000000-0000-4000-8000-000000000001'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('40000000-0000-4000-8000-000000000001'),'RESERVED',0,1048576,REPEAT('a',64),'tmp/one','final/one',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY),
  (UUID_TO_BIN('50000000-0000-4000-8000-000000000002'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('40000000-0000-4000-8000-000000000002'),'UPLOADING',1,1048576,REPEAT('b',64),'tmp/two','final/two',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY);
"

expect_rejected \
  "same recording has at most one active upload" \
  "UPDATE recording_upload SET state='COMMITTED',active_slot=NULL,reservation_released_at=UTC_TIMESTAMP(3) WHERE id=UUID_TO_BIN('50000000-0000-4000-8000-000000000002'); INSERT INTO recording_upload (id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,temp_key,final_key,policy_revision,expires_at) VALUES (UUID_TO_BIN('50000000-0000-4000-8000-000000000003'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('40000000-0000-4000-8000-000000000001'),'RESERVED',1,1048576,REPEAT('c',64),'tmp/three','final/three',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY);"

run_sql "
INSERT INTO recording_upload (
  id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,
  temp_key,final_key,policy_revision,expires_at
) VALUES (
  UUID_TO_BIN('50000000-0000-4000-8000-000000000004'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('40000000-0000-4000-8000-000000000003'),
  'VERIFYING',1,1048576,REPEAT('d',64),'tmp/four','final/four',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY
);
"

expect_rejected \
  "account has only two active upload slots" \
  "INSERT INTO recording_upload (id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,temp_key,final_key,policy_revision,expires_at) VALUES (UUID_TO_BIN('50000000-0000-4000-8000-000000000005'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('40000000-0000-4000-8000-000000000002'),'RESERVED',0,1048576,REPEAT('e',64),'tmp/five','final/five',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY);"
expect_rejected \
  "terminal upload cannot occupy an active slot" \
  "INSERT INTO recording_upload (id,user_id,recording_id,state,active_slot,expected_size,expected_sha256,temp_key,final_key,policy_revision,expires_at) VALUES (UUID_TO_BIN('50000000-0000-4000-8000-000000000006'),UUID_TO_BIN('10000000-0000-4000-8000-000000000001'),UUID_TO_BIN('40000000-0000-4000-8000-000000000002'),'FAILED',1,1048576,REPEAT('f',64),'tmp/six','final/six',1,UTC_TIMESTAMP(3)+INTERVAL 1 DAY);"

expect_value \
  "same email is allowed for separate identities" \
  "SELECT COUNT(*) FROM auth_identity WHERE email='same@example.com';" \
  "2"
expect_value \
  "same TJ number is allowed in separate accounts" \
  "SELECT COUNT(*) FROM song WHERE tj_number='00123' AND lifecycle_state='ACTIVE';" \
  "2"
expect_value \
  "valid SAVED recording retained its immutable file spec" \
  "SELECT CONCAT(r.metadata_state,':',f.size_bytes) FROM recording r JOIN recording_file_spec f ON f.recording_id=r.id WHERE r.id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');" \
  "SAVED:1048576"

echo "P04-01~03 MySQL schema verification passed."
