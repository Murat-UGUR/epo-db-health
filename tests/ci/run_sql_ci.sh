#!/usr/bin/env bash
# Runs every script in sql/ against a SQL Server container (GitHub Actions service) loaded with a
# mock ePO schema, fails on any T-SQL error, then checks the outputs contain the expected findings.
# Usage: tests/ci/run_sql_ci.sh <container-id> <sa-password>
set -euo pipefail
CID="$1"
PW="$2"
OUT="ci-output"
mkdir -p "$OUT"

if docker exec "$CID" test -x /opt/mssql-tools18/bin/sqlcmd; then
  SQLCMD=(/opt/mssql-tools18/bin/sqlcmd -C)
else
  SQLCMD=(/opt/mssql-tools/bin/sqlcmd)
fi
q() { docker exec "$CID" "${SQLCMD[@]}" -S localhost -U sa -P "$PW" -b "$@"; }

echo "Waiting for SQL Server..."
for i in $(seq 1 60); do
  if q -Q "SELECT 1" > /dev/null 2>&1; then echo "SQL Server is up."; break; fi
  if [ "$i" -eq 60 ]; then echo "::error::SQL Server did not start"; exit 1; fi
  sleep 2
done
q -h -1 -Q "SET NOCOUNT ON; SELECT @@VERSION"

docker exec "$CID" mkdir -p /tmp/epo
docker cp sql/. "$CID":/tmp/epo/
docker cp tests/ci/mock_epo_schema.sql "$CID":/tmp/epo/mock_epo_schema.sql

echo "::group::Load mock ePO schema"
q -i /tmp/epo/mock_epo_schema.sql
echo "::endgroup::"

fail=0
for f in sql/*.sql; do
  name="$(basename "$f")"
  echo "::group::$name"
  if q -d ePO_CI -W -s '|' -i "/tmp/epo/$name" > "$OUT/$name.txt" 2>&1; then
    cat "$OUT/$name.txt"
    echo "PASS: $name"
  else
    cat "$OUT/$name.txt"
    echo "::error file=sql/$name::$name failed to execute"
    fail=1
  fi
  echo "::endgroup::"
done

expect() {  # expect <file> <pattern> <message>
  if grep -q -- "$2" "$OUT/$1.txt"; then echo "OK   $1: $3"; else echo "::error file=sql/$1::$3 (pattern '$2' not found)"; fail=1; fi
}
reject() {  # reject <file> <pattern> <message>
  if grep -q -- "$2" "$OUT/$1.txt"; then echo "::error file=sql/$1::$3 (pattern '$2' found)"; fail=1; else echo "OK   $1: $3"; fi
}

echo "--- Assertions ---"
expect 00_overview.sql          "ePO_CI"            "reports the current database"
expect 01_table_sizes.sql       "CI_FragTest"       "lists the largest table"
expect 02_index_fragmentation.sql "REBUILD"         "flags the fragmented index for REBUILD"
expect 03_event_volume.sql      "1092"              "finds the noisiest event ID"
expect 04_stale_agents.sql      "STALE-HOST-01"     "lists a host silent for 10 days"
expect 04_stale_agents.sql      "STALE-HOST-02"     "lists a host silent for 45 days"
reject 04_stale_agents.sql      "FRESH-HOST-01"     "does not list a host that checked in 2 hours ago"
expect 04_stale_agents.sql      "5 - never"         "counts the host that never communicated"
expect 06_backup_history.sql    "ePO_CI CI backup\|ePO_CI.bak" "shows the recorded backup"
expect 06_backup_history.sql    "WARNING: FULL"     "warns about FULL recovery without log backups"

exit $fail
