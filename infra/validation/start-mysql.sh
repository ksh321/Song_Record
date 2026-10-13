#!/bin/sh
set -eu
attempt=0
while [ ! -f /run/runtime/ready ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -gt 120 ]; then echo 'Database configuration unavailable; startup refused' >&2; exit 1; fi
  sleep 1
done
exec /usr/local/bin/docker-entrypoint.sh mysqld --character-set-server=utf8mb4 --collation-server=utf8mb4_0900_ai_ci --default-time-zone=+00:00 --log-bin-trust-function-creators=1
