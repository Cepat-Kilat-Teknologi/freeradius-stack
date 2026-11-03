#!/bin/bash
# radacct maintenance — purge stale sessions and auth logs.
#
# Usage (Docker standalone):
#   docker exec radius-mariadb sh -c 'MYSQL_USER=root MYSQL_PASSWORD="$MARIADB_ROOT_PASSWORD" MYSQL_DBNAME=radius /scripts/maintenance.sh'
#
# Usage (Kubernetes):
#   Runs inside the maintenance CronJob container with env vars from ConfigMap/Secret.
#
# Environment variables:
#   MYSQL_HOST     (default: localhost)
#   MYSQL_PORT     (default: 3306)
#   MYSQL_USER     (required)
#   MYSQL_PASSWORD (required)
#   MYSQL_DBNAME   (default: radius)
#   RADACCT_RETENTION_DAYS      (default: 90)  — delete closed sessions older than this
#   STALE_SESSION_DAYS          (default: 90)  — delete stale open sessions (no update) older than this
#   RADPOSTAUTH_RETENTION_DAYS  (default: 30)  — delete auth logs older than this
#   BATCH_SIZE                  (default: 50000)
#   SKIP_SSL                    (default: true) — pass --skip-ssl to mariadb client

set -euo pipefail

MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_DBNAME="${MYSQL_DBNAME:-radius}"
RADACCT_RETENTION_DAYS="${RADACCT_RETENTION_DAYS:-90}"
STALE_SESSION_DAYS="${STALE_SESSION_DAYS:-90}"
RADPOSTAUTH_RETENTION_DAYS="${RADPOSTAUTH_RETENTION_DAYS:-30}"
BATCH_SIZE="${BATCH_SIZE:-50000}"
SKIP_SSL="${SKIP_SSL:-true}"

if [ -z "${MYSQL_USER:-}" ] || [ -z "${MYSQL_PASSWORD:-}" ]; then
  echo "Error: MYSQL_USER and MYSQL_PASSWORD are required" >&2
  exit 1
fi

SSL_FLAG=""
if [ "$SKIP_SSL" = "true" ]; then
  SSL_FLAG="--skip-ssl"
fi

DB="mariadb -h $MYSQL_HOST -P $MYSQL_PORT -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DBNAME $SSL_FLAG"

run_sql() {
  $DB -N -e "$1"
}

run_sql_silent() {
  $DB -e "$1" 2>/dev/null
}

echo "=== radacct maintenance started at $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
echo "Database: $MYSQL_DBNAME@$MYSQL_HOST:$MYSQL_PORT"

# --- 1. Delete CLOSED sessions older than retention period ---
echo ""
echo "=== Phase 1: closed sessions older than ${RADACCT_RETENTION_DAYS} days ==="

TOTAL=0
while true; do
  DELETED=$(run_sql \
    "DELETE FROM radacct WHERE acctstoptime IS NOT NULL AND acctstoptime < DATE_SUB(NOW(), INTERVAL $RADACCT_RETENTION_DAYS DAY) LIMIT $BATCH_SIZE; SELECT ROW_COUNT();")
  TOTAL=$((TOTAL + DELETED))
  echo "  deleted batch: $DELETED (total: $TOTAL)"
  [ "$DELETED" -lt "$BATCH_SIZE" ] && break
  sleep 1
done
echo "Phase 1 complete: $TOTAL closed sessions deleted"

# --- 2. Delete STALE open sessions (no accounting update) ---
echo ""
echo "=== Phase 2: stale open sessions (no update for ${STALE_SESSION_DAYS}+ days) ==="

TOTAL=0
while true; do
  DELETED=$(run_sql \
    "DELETE FROM radacct WHERE acctstoptime IS NULL AND acctupdatetime < DATE_SUB(NOW(), INTERVAL $STALE_SESSION_DAYS DAY) LIMIT $BATCH_SIZE; SELECT ROW_COUNT();")
  TOTAL=$((TOTAL + DELETED))
  echo "  deleted batch: $DELETED (total: $TOTAL)"
  [ "$DELETED" -lt "$BATCH_SIZE" ] && break
  sleep 1
done
echo "Phase 2 complete: $TOTAL stale sessions deleted"

# --- 3. Delete DUPLICATE active sessions per user per NAS (keep newest) ---
echo ""
echo "=== Phase 3: duplicate active sessions (keep newest per user/NAS) ==="

# Two-phase approach: SELECT IDs first, then DELETE by PK in batches.
# Avoids deadlocks on self-JOIN (important for Galera; safe for standalone too).
DELETE_IDS=$(run_sql \
  "SELECT r.radacctid FROM radacct r WHERE r.acctstoptime IS NULL AND r.radacctid NOT IN (SELECT MAX(radacctid) FROM radacct WHERE acctstoptime IS NULL GROUP BY username, nasipaddress) ORDER BY r.radacctid;")
TOTAL_DUPES=$(echo "$DELETE_IDS" | grep -c '[0-9]' || true)
echo "  found $TOTAL_DUPES duplicate sessions"

if [ "$TOTAL_DUPES" -gt 0 ]; then
  TOTAL=0
  BATCH=""
  COUNT=0
  for ID in $DELETE_IDS; do
    BATCH="${BATCH:+$BATCH,}$ID"
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge 100 ]; then
      for RETRY in 1 2 3; do
        if run_sql_silent "DELETE FROM radacct WHERE radacctid IN ($BATCH);"; then
          TOTAL=$((TOTAL + COUNT))
          break
        fi
        echo "  retry $RETRY on deadlock..."
        sleep "$RETRY"
      done
      echo "  deleted batch: $COUNT (total: $TOTAL)"
      COUNT=0
      BATCH=""
      sleep 0.5
    fi
  done
  if [ -n "$BATCH" ]; then
    for RETRY in 1 2 3; do
      run_sql_silent "DELETE FROM radacct WHERE radacctid IN ($BATCH);" && break
      sleep "$RETRY"
    done
    TOTAL=$((TOTAL + COUNT))
  fi
  echo "Phase 3 complete: $TOTAL duplicate sessions deleted"
else
  echo "Phase 3 complete: no duplicates found"
fi

# --- 4. Delete old radpostauth logs ---
echo ""
echo "=== Phase 4: radpostauth logs older than ${RADPOSTAUTH_RETENTION_DAYS} days ==="

TOTAL=0
while true; do
  DELETED=$(run_sql \
    "DELETE FROM radpostauth WHERE authdate < DATE_SUB(NOW(), INTERVAL $RADPOSTAUTH_RETENTION_DAYS DAY) LIMIT $BATCH_SIZE; SELECT ROW_COUNT();")
  TOTAL=$((TOTAL + DELETED))
  echo "  deleted batch: $DELETED (total: $TOTAL)"
  [ "$DELETED" -lt "$BATCH_SIZE" ] && break
  sleep 1
done
echo "Phase 4 complete: $TOTAL auth log rows deleted"

echo ""
echo "=== maintenance done at $(date '+%Y-%m-%d %H:%M:%S %Z') ==="

# Summary
ACTIVE=$(run_sql "SELECT COUNT(*) FROM radacct WHERE acctstoptime IS NULL;")
TOTAL_ROWS=$(run_sql "SELECT COUNT(*) FROM radacct;")
echo "radacct: $TOTAL_ROWS total rows, $ACTIVE active sessions"
