#!/usr/bin/env bash
set -euo pipefail

INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"

echo "Starting infinite insert loop into PostgreSQL every ${INTERVAL_SECONDS}s..."
echo "Host: ${PGHOST:-localhost} DB: ${PGDATABASE:-postgres} User: ${PGUSER:-postgres}"

while true; do
  psql -v ON_ERROR_STOP=1 -c "SELECT generate_telco_batch();"
  sleep "${INTERVAL_SECONDS}"
done