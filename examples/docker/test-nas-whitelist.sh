#!/usr/bin/env bash
# NAS whitelist tenant isolation test, run against the docker compose stack.
#
# Proves the authorize check injected by scripts/entrypoint.sh rejects a user
# on a NAS that is not in user_nas_whitelist, accepts it on a whitelisted NAS,
# leaves users without whitelist rows unrestricted, and escapes the username
# (a quote in the name must still match its own rows, not break the query).
#
# Usage (from examples/docker, stack up and healthy):
#   MYSQL_ROOT_PASSWORD=... RADIUS_SECRET=... ./test-nas-whitelist.sh
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?set MYSQL_ROOT_PASSWORD}"
: "${RADIUS_SECRET:?set RADIUS_SECRET}"
DB="${MYSQL_DBNAME:-radius}"

sql() { docker compose exec -T db mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$DB" -e "$1"; }

# Same shape as freeradius-api migration 000004.
sql "CREATE TABLE IF NOT EXISTS user_nas_whitelist (
  id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  username varchar(64) NOT NULL,
  nasipaddress varchar(15) NOT NULL,
  organization_id varchar(36) DEFAULT NULL,
  created_at timestamp NULL DEFAULT current_timestamp(),
  UNIQUE KEY uk_user_nas (username, nasipaddress));"

sql "INSERT INTO radcheck (username, attribute, op, value) VALUES
  ('wl_user', 'Cleartext-Password', ':=', 'changeme'),
  ('wl''quote', 'Cleartext-Password', ':=', 'changeme'),
  ('free_user', 'Cleartext-Password', ':=', 'changeme')
  ON DUPLICATE KEY UPDATE value = VALUES(value);"
sql "INSERT IGNORE INTO user_nas_whitelist (username, nasipaddress) VALUES
  ('wl_user', '10.0.0.1'), ('wl_user', '10.0.0.3'), ('wl''quote', '10.0.0.1');"

fail=0
# expect <Access-Accept|Access-Reject> <user> <password> <nas-ip>
expect() {
  local want=$1 user=$2 pass=$3 nas=$4 got
  got=$(printf 'User-Name = "%s"\nUser-Password = "%s"\nNAS-IP-Address = %s\n' "$user" "$pass" "$nas" \
    | docker compose exec -T freeradius radclient -t 3 -r 1 127.0.0.1:1812 auth "$RADIUS_SECRET" 2>&1 \
    | grep -oE 'Access-(Accept|Reject)' | tail -1 || true)
  if [ "$got" = "$want" ]; then
    echo "PASS  $user via $nas -> $got"
  else
    echo "FAIL  $user via $nas -> ${got:-no reply} (want $want)"
    fail=1
  fi
}

expect Access-Accept wl_user   changeme 10.0.0.1   # whitelisted NAS
expect Access-Accept wl_user   changeme 10.0.0.3   # second whitelisted NAS
expect Access-Reject wl_user   changeme 10.0.0.2   # NAS not in whitelist
expect Access-Accept "wl'quote" changeme 10.0.0.1   # quote escaped, own row matches
expect Access-Reject "wl'quote" changeme 10.0.0.2   # and is still enforced
expect Access-Accept free_user changeme 10.0.0.2   # no whitelist rows: unrestricted

exit "$fail"
