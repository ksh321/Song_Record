#!/usr/bin/env bash
set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$infra_dir/.." && pwd)"
api_jar="$repo_root/services/api/build/libs/api-0.0.1-SNAPSHOT.jar"
api_log="$(mktemp)"
api_pid=""

cleanup() {
  if [[ -n "$api_pid" ]] && kill -0 "$api_pid" 2>/dev/null; then
    kill "$api_pid"
    wait "$api_pid" 2>/dev/null || true
  fi
  rm -f "$api_log"
}
trap cleanup EXIT

: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"
if [[ "${P04_DISPOSABLE_DB:-}" != "1" ]]; then
  echo "Use a disposable test DB and set P04_DISPOSABLE_DB=1. Never run on user data."
  exit 1
fi
api_port="${P04_API_PORT:-18084}"
# A per-run test-only key; never reuse as a deployed secret.
export SONGRECORD_PAGINATION_KEY_BASE64="$(python3 -c 'import base64,secrets; print(base64.b64encode(secrets.token_bytes(32)).decode())')"

run_sql() {
  docker compose exec -T mysql sh -lc \
    'MYSQL_PWD="$MYSQL_PASSWORD" mysql --protocol=tcp -h127.0.0.1 -u"$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names' \
    <<<"$1"
}

start_api() {
  local flyway_target="$1"
  : >"$api_log"
  if [[ -n "$flyway_target" ]]; then
    SPRING_FLYWAY_TARGET="$flyway_target" \
    SPRING_PROFILES_ACTIVE=dev \
    DB_HOST=127.0.0.1 \
    DB_PORT="${MYSQL_PORT:-3306}" \
    DB_NAME="$MYSQL_DATABASE" \
    DB_USER="$MYSQL_USER" \
    DB_PASSWORD="$DB_PASSWORD" \
    SERVER_PORT="$api_port" \
      java -jar "$api_jar" >"$api_log" 2>&1 &
  else
    SPRING_PROFILES_ACTIVE=dev \
    DB_HOST=127.0.0.1 \
    DB_PORT="${MYSQL_PORT:-3306}" \
    DB_NAME="$MYSQL_DATABASE" \
    DB_USER="$MYSQL_USER" \
    DB_PASSWORD="$DB_PASSWORD" \
    SERVER_PORT="$api_port" \
      java -jar "$api_jar" >"$api_log" 2>&1 &
  fi
  api_pid=$!

  for attempt in {1..60}; do
    if kill -0 "$api_pid" 2>/dev/null \
       && grep -q 'Started ApiApplication' "$api_log" \
       && curl --fail --silent "http://127.0.0.1:$api_port/actuator/health" >/dev/null; then
      return 0
    fi
    if ! kill -0 "$api_pid" 2>/dev/null; then
      echo "API stopped before becoming healthy."
      cat "$api_log"
      exit 1
    fi
    sleep 1
  done

  echo "API did not become healthy in time."
  cat "$api_log"
  exit 1
}

stop_api() {
  if [[ -n "$api_pid" ]] && kill -0 "$api_pid" 2>/dev/null; then
    kill "$api_pid"
    wait "$api_pid" 2>/dev/null || true
  fi
  api_pid=""
}

if [[ ! -f "$api_jar" ]]; then
  echo "Missing API boot jar: $api_jar"
  exit 1
fi

cd "$infra_dir"

start_api "1"
run_sql "INSERT INTO app_schema_metadata (schema_key,schema_value) VALUES ('upgrade_sentinel','kept');"
stop_api

start_api "2"
stop_api

bash "$infra_dir/scripts/verify_p04_core_schema.sh"

# Verify preservation of an actual V2 asset, not just an empty baseline table.
run_sql "UPDATE recording_asset SET cloud_state='STORED',object_key='upgrade/legacy',generation=7,verified_size=1048576,sha256=REPEAT('a',64),stored_at=UTC_TIMESTAMP(3) WHERE recording_id=UUID_TO_BIN('40000000-0000-4000-8000-000000000001');"
start_api "4"
stop_api
legacy="$(run_sql "SELECT CONCAT(object_key,':',legacy_generation,':',OCTET_LENGTH(generation),':',verified_size) FROM recording_asset WHERE object_key='upgrade/legacy';")"
[[ "$legacy" == "upgrade/legacy:7:16:1048576" ]] || { echo "Legacy asset was not preserved"; exit 1; }
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
python3 "$infra_dir/scripts/verify_p04_extended_schema.py"

# Upgrade populated V4 data: usage must be backfilled, not reset to zero.
python3 "$infra_dir/scripts/verify_p04_retention_schema.py" --seed-upgrade
start_api "5"
stop_api
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4,5" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
python3 "$infra_dir/scripts/verify_p04_retention_schema.py"

python3 "$infra_dir/scripts/verify_p04_sync_schema.py" --seed-upgrade
start_api "6"
stop_api
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4,5,6" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
python3 "$infra_dir/scripts/verify_p04_sync_schema.py"

python3 "$infra_dir/scripts/verify_p04_snapshot_schema.py" --seed-upgrade
start_api "7"
stop_api
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4,5,6,7" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
python3 "$infra_dir/scripts/verify_p04_snapshot_schema.py"

# Keep historical checks pinned, then test the populated V7 -> V8 upgrade.
python3 "$infra_dir/scripts/verify_p06_session_schema.py" --seed-upgrade
start_api "8"
stop_api
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4,5,6,7,8" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
python3 "$infra_dir/scripts/verify_p06_session_schema.py"

python3 "$infra_dir/scripts/verify_p06_link_schema.py" --seed-upgrade
start_api "9"
stop_api
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4,5,6,7,8,9" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
python3 "$infra_dir/scripts/verify_p06_link_schema.py"

# Populated V9 -> V19: preserve metadata and fill song/recording keys before serving lists.
start_api ""
stop_api
versions="$(run_sql "SELECT GROUP_CONCAT(version ORDER BY installed_rank) FROM flyway_schema_history WHERE success=1;")"
[[ "$versions" == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20" ]] || { echo "Unexpected Flyway versions: $versions"; exit 1; }
missing_keys="$(run_sql "SELECT COUNT(*) FROM song s LEFT JOIN song_query_key k ON k.song_id=s.id AND k.user_id=s.user_id WHERE k.song_id IS NULL OR k.key_version<>'SR-SORT-1/SR-SORT-BYTES-1';")"
[[ "$missing_keys" == "0" ]] || { echo "Song key backfill is incomplete"; exit 1; }
missing_recording_keys="$(run_sql "SELECT COUNT(*) FROM recording r LEFT JOIN recording_query_key k ON k.recording_id=r.id AND k.user_id=r.user_id WHERE k.recording_id IS NULL OR k.key_version<>'SR-SORT-1/SR-SORT-BYTES-1';")"
[[ "$missing_recording_keys" == "0" ]] || { echo "Recording key backfill is incomplete"; exit 1; }
# Re-start against the same data: Flyway must validate existing checksums.
start_api ""
stop_api
echo "P04-01~07 upgrade, constraints and restart verification passed."
