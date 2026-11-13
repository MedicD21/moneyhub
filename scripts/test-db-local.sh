#!/usr/bin/env bash
# Run the Phase 1/2 SQL test suite against a throwaway local Postgres cluster
# (no Docker needed). Requires: postgresql-16 (or newer), postgresql-<v>-pgtap,
# postgresql-<v>-cron, and pg_prove.
#
#   scripts/test-db-local.sh            # run all tests
#   KEEP=1 scripts/test-db-local.sh     # leave the cluster running afterwards
#
# With Docker + Supabase CLI you can instead run:  supabase start && supabase test db
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
PORT="${PORT:-54329}"
DATA="$(mktemp -d /tmp/moneyhub-pg.XXXXXX)"
RUN_AS=()
if [ "$(id -u)" = "0" ]; then
  chown postgres:postgres "$DATA"
  RUN_AS=(runuser -u postgres --)
fi

cleanup() {
  if [ "${KEEP:-0}" != "1" ]; then
    "${RUN_AS[@]}" "$PGBIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1 || true
    rm -rf "$DATA"
  else
    echo "Cluster left running: psql -h $DATA -p $PORT -U postgres postgres"
  fi
}
trap cleanup EXIT

"${RUN_AS[@]}" "$PGBIN/initdb" -D "$DATA" -U postgres --auth=trust >/dev/null
cat >> "$DATA/postgresql.conf" <<CONF
port = $PORT
listen_addresses = ''
unix_socket_directories = '$DATA'
shared_preload_libraries = 'pg_cron'
cron.database_name = 'postgres'
timezone = 'UTC'
CONF
"${RUN_AS[@]}" "$PGBIN/pg_ctl" -D "$DATA" -l "$DATA/server.log" -w start >/dev/null

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$DATA" -p "$PORT" -U postgres -d postgres)

echo "==> Supabase shim"
"${PSQL[@]}" -f "$ROOT/scripts/local/supabase_shim.sql"

echo "==> Migrations"
# Seed rows (e.g. paid_holidays) default owner_id to app_owner_id(), which is null in an empty database.
# Production had an owner when they ran; give this throwaway cluster a placeholder JWT subject instead.
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "    $(basename "$f")"
  PGOPTIONS="-c request.jwt.claim.sub=00000000-0000-0000-0000-00000000dead" "${PSQL[@]}" -f "$f"
done

echo "==> Tests"
pg_prove -h "$DATA" -p "$PORT" -U postgres -d postgres --ext .sql -r "$ROOT/supabase/tests/database"
