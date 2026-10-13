#!/bin/sh
set -eu
# Inject through sealed stdin into tmpfs before starting, never via Docker argv or environment.
attempt=0
while [ ! -f /run/runtime/ready ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -gt 120 ]; then echo 'Runtime configuration unavailable; startup refused' >&2; exit 1; fi
  sleep 1
done
exec java -XX:MaxRAMPercentage=60 -Djava.io.tmpdir=/tmp -jar /app/api.jar
