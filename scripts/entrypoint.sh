#!/bin/bash
set -eo pipefail

# FreeRADIUS config directory detection
# Debian packages: /etc/freeradius/3.0/
# Source install: /etc/raddb/
if [[ -d "/etc/freeradius/3.0" ]]; then
    RADDB_DIR="/etc/freeradius/3.0"
elif [[ -d "/etc/freeradius" ]]; then
    RADDB_DIR="/etc/freeradius"
elif [[ -d "/etc/raddb" ]]; then
    RADDB_DIR="/etc/raddb"
else
    echo "Error: Could not find FreeRADIUS config directory" >&2
    exit 1
fi

echo "Using FreeRADIUS config directory: $RADDB_DIR"

# Validate required environment variables
required_vars=("MYSQL_HOST" "MYSQL_PORT" "MYSQL_USER" "MYSQL_PASSWORD" "MYSQL_DBNAME" "RADIUS_SECRET")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "Error: Required environment variable $var is not set." >&2
        exit 1
    fi
done

# Reject placeholder values in production
for var in "${required_vars[@]}"; do
    if [[ "${!var}" == CHANGE_ME_* ]]; then
        echo "Error: $var still has placeholder value '${!var}'. Set a real value." >&2
        exit 1
    fi
done

# Validate MYSQL_DBNAME format (alphanumeric and underscore only, prevent SQL injection)
if [[ ! "$MYSQL_DBNAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "Error: MYSQL_DBNAME contains invalid characters. Only alphanumeric and underscore allowed." >&2
    exit 1
fi

# Validate MYSQL_PORT is numeric
if [[ ! "$MYSQL_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: MYSQL_PORT must be numeric." >&2
    exit 1
fi

# Create a MySQL credentials file to avoid deprecated MYSQL_PWD env var
create_mysql_creds() {
    local creds_file="/tmp/.mysql-creds-$$"
    cat > "$creds_file" <<CREDS
[client]
password=${MYSQL_PASSWORD}
CREDS
    chmod 600 "$creds_file"
    echo "$creds_file"
}
MYSQL_CREDS_FILE=$(create_mysql_creds)

# ISS-08b: Make MySQL TLS configurable instead of hardcoded off
MYSQL_SSL_OPTS="${MYSQL_SSL_OPTS:---skip-ssl}"
if [[ -n "${MYSQL_TLS_CA:-}" ]]; then
    MYSQL_SSL_OPTS="--ssl-ca=${MYSQL_TLS_CA}"
    [[ -n "${MYSQL_TLS_CERT:-}" ]] && MYSQL_SSL_OPTS="$MYSQL_SSL_OPTS --ssl-cert=${MYSQL_TLS_CERT}"
    [[ -n "${MYSQL_TLS_KEY:-}" ]] && MYSQL_SSL_OPTS="$MYSQL_SSL_OPTS --ssl-key=${MYSQL_TLS_KEY}"
fi

# Set timezone if provided
if [[ -n "$TZ" ]]; then
    ln -fs /usr/share/zoneinfo/"$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# Redis accounting configuration (optional, default: disabled)
# When enabled, Interim-Update packets are buffered in Redis for batch processing
ACCT_REDIS_ENABLED="${ACCT_REDIS_ENABLED:-false}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_DB="${REDIS_DB:-0}"

# Warn if HEALTHCHECK_SECRET is still the default value
if [[ "$HEALTHCHECK_SECRET" == "testing123" ]] || [[ "$HEALTHCHECK_SECRET" == "CHANGE_ME_HEALTHCHECK_SECRET" ]]; then
    echo "WARNING: HEALTHCHECK_SECRET is using default value. Set a unique value in production." >&2
fi

echo "Starting FreeRADIUS initialization..."

# Wait for MySQL with proper timeout handling
echo "Waiting for MySQL to be ready..."
mysql_ready=false
for i in {1..30}; do
    if mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=5 -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -e "SELECT 1" &>/dev/null; then
        echo "MySQL is ready."
        mysql_ready=true
        break
    fi
    echo "  Waiting ($i/30)..."
    sleep 2
done

if [[ "$mysql_ready" != "true" ]]; then
    echo "Error: MySQL did not become ready within 60 seconds." >&2
    exit 1
fi

# Wait for Redis if accounting Redis is enabled
if [[ "$ACCT_REDIS_ENABLED" == "true" ]]; then
    echo "Redis accounting enabled. Waiting for Redis..."
    redis_ready=false
    for i in {1..15}; do
        if (echo -e "PING\r" | timeout 3 bash -c "exec 3<>/dev/tcp/$REDIS_HOST/$REDIS_PORT; cat >&3; head -1 <&3") 2>/dev/null | grep -q PONG; then
            echo "Redis is ready."
            redis_ready=true
            break
        fi
        echo "  Waiting for Redis ($i/15)..."
        sleep 2
    done

    if [[ "$redis_ready" != "true" ]]; then
        echo "Warning: Redis not available. Accounting will fall back to SQL only." >&2
        ACCT_REDIS_ENABLED="false"
    fi
fi

# Function to check if schema already exists
schema_exists() {
    local table_count
    table_count=$(mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=10 -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DBNAME' AND table_name='radcheck';" 2>/dev/null || echo "0")
    [[ "$table_count" -gt 0 ]]
}

# Function to acquire lock using MySQL (works across pods)
acquire_db_lock() {
    local lock_name="freeradius_init_lock"
    local lock_timeout=30
    local result
    result=$(mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=10 -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" -N -e "SELECT GET_LOCK('$lock_name', $lock_timeout);" 2>/dev/null || echo "0")
    [[ "$result" == "1" ]]
}

# Function to release lock
release_db_lock() {
    local lock_name="freeradius_init_lock"
    mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=10 -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" -N -e "SELECT RELEASE_LOCK('$lock_name');" &>/dev/null || true
}

# Run post-schema migrations (InnoDB conversion, additional indexes)
# Safe to run multiple times - ALTER TABLE ENGINE=InnoDB is a no-op if already InnoDB,
# CREATE INDEX will fail silently with --force if index already exists.
run_post_schema_migrations() {
    local migration_file="/entrypoint-post-schema.sql"
    if [[ ! -f "$migration_file" ]]; then
        echo "No post-schema migration file found. Skipping."
        return 0
    fi

    echo "Running post-schema migrations..."
    if mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=10 \
        --force -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" < "$migration_file" 2>&1; then
        echo "Post-schema migrations applied successfully."
    else
        echo "Post-schema migrations completed (some statements may have been skipped as already applied)."
    fi
}

# Use local file lock for config modifications (per-container)
mkdir -p "${RADDB_DIR}/custom"
LOCAL_LOCK_FILE="${RADDB_DIR}/custom/init.lock"

cd "$RADDB_DIR" || { echo "Failed to cd $RADDB_DIR"; exit 1; }

# Always ensure essential modules are enabled (sites-enabled can be reset on container recreate)
if [[ -f "mods-available/sql" ]] && [[ ! -L "mods-enabled/sql" ]]; then
    echo "Enabling SQL module..."
    ln -sf "${RADDB_DIR}/mods-available/sql" "${RADDB_DIR}/mods-enabled/sql"
fi

if [[ -f "sites-available/status" ]] && [[ ! -L "sites-enabled/status" ]]; then
    echo "Enabling Status Server..."
    ln -sf "${RADDB_DIR}/sites-available/status" "${RADDB_DIR}/sites-enabled/status"
fi

# Escape helper functions
escape_for_sed() {
    printf '%s\n' "$1" | sed -e 's/[\/&.*[\]^$|]/\\&/g'
}
escape_for_freeradius_quoted() {
    printf '%s\n' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Always update admin client secret to match HEALTHCHECK_SECRET for healthcheck to work
healthcheck_secret="${HEALTHCHECK_SECRET:-testing123}"
if [[ -f "sites-available/status" ]]; then
    echo "Updating status server admin secret..."
    # Escape special characters for sed replacement (handle all sed special chars)
    escaped_healthcheck_secret=$(printf '%s\n' "$healthcheck_secret" | sed -e 's/[\/&.*[\]^$]/\\&/g')
    sed -Ei "/client admin/,/\}/s/secret = .*/secret = ${escaped_healthcheck_secret}/" "sites-available/status"
fi

# =============================================================================
# SQL module config substitution (RUNS ON EVERY START)
# =============================================================================
# This block intentionally lives OUTSIDE the LOCAL_LOCK_FILE guard below.
# Reason: when the freeradius image is rebuilt or the container is recreated
# (e.g. `docker compose up -d --build`), the new container starts with a
# fresh writable layer where mods-available/sql is the IMAGE default
# (dialect=sqlite, driver=rlm_sql_null). The lock file is persisted on the
# `freeradius_config` volume, so it survives the recreate. If the SQL
# substitution were gated by the lock, the new container would skip the
# substitution and FreeRADIUS would boot with the null driver — silently
# losing all SQL functionality (clients from `nas` table not loaded, NAS
# auth requests rejected as "unknown client", `radcheck` lookups bypassed).
#
# Idempotency: we detect whether the file has already been configured by
# checking for the substituted `dialect = "mysql"` marker. If present, the
# substitution has already run on a previous start and we skip the sed
# block to avoid double-application (notably the TLS-section commenting
# pass, which is non-idempotent because BusyBox sed lacks an easy way to
# express "comment only if not already commented" without nested {} blocks
# that have edge cases on closing braces).
#
# We patch `mods-available/sql` directly (not the `mods-enabled/sql`
# symlink) because BusyBox `sed -i` REPLACES symlinks with regular files
# instead of following them, which on a subsequent restart would be
# clobbered by the `ln -sf` re-symlink step above. Patching the underlying
# file keeps the symlink stable.

echo "Enabling SQL module in sites-enabled/default..."
if [[ -f "sites-enabled/default" ]]; then
    sed -Ei 's/#[\t ]*sql$/sql/g' sites-enabled/default

    # SECURITY (fail-closed auth): reject any request that reaches the end of the
    # `authorize` section without a credential loaded from the database. Without
    # this guard an unknown user -- or a degraded SQL backend -- can fall through
    # to Access-Accept. Fail-closed is the correct posture for an ISP: when no
    # credential is known, reject. Idempotent across restarts.
    if ! grep -q "fail-closed-auth" sites-enabled/default; then
        echo "Hardening authorize: reject users without a database credential (fail-closed)..."
        awk '
            /^authorize[ \t]*\{/ { in_authz = 1 }
            in_authz && /^\}/ {
                print "\t# fail-closed-auth: no credential from the DB => reject (never accept-all)"
                print "\tif (!&control:Cleartext-Password && !&control:Crypt-Password && !&control:NT-Password && !&control:Password-With-Header) {"
                print "\t\treject"
                print "\t}"
                in_authz = 0
            }
            { print }
        ' sites-enabled/default > sites-enabled/default.tmp && mv sites-enabled/default.tmp sites-enabled/default
    fi

    # NAS whitelist tenant isolation: reject users whose NAS is not in whitelist.
    # The user_nas_whitelist table is managed by freeradius-api (migration 000004).
    # Logic: if the user has ANY whitelist entries but the requesting NAS is not
    # among them, reject. Users without whitelist entries are unrestricted.
    # Graceful degradation: if table doesn't exist yet, SQL returns empty string
    # which != "0" is true, but inner query also returns "" which == "0" is false,
    # so auth continues normally (no blocking when table is missing).
    # Idempotent: skipped if already injected from a previous start.
    if ! grep -q "nas-whitelist-check" sites-enabled/default; then
        echo "Hardening authorize: adding NAS whitelist tenant isolation check..."
        awk '
            /^authorize[ \t]*\{/ { in_authz = 1 }
            in_authz && /^[[:space:]]*sql[[:space:]]*$/ && !nas_done {
                print
                print ""
                print "\t# nas-whitelist-check: tenant isolation -- reject if user has NAS restrictions and this NAS is not allowed"
                print "\tif (\"%{sql:SELECT COUNT(*) FROM user_nas_whitelist WHERE username=\047%{User-Name}\047}\" != \"0\") {"
                print "\t\tif (\"%{sql:SELECT COUNT(*) FROM user_nas_whitelist WHERE username=\047%{User-Name}\047 AND nasipaddress=\047%{NAS-IP-Address}\047}\" == \"0\") {"
                print "\t\t\tupdate reply {"
                print "\t\t\t\t&Reply-Message := \"NAS not authorized for this user\""
                print "\t\t\t}"
                print "\t\t\treject"
                print "\t\t}"
                print "\t}"
                nas_done = 1
                next
            }
            in_authz && /^\}/ { in_authz = 0 }
            { print }
        ' sites-enabled/default > sites-enabled/default.tmp && mv sites-enabled/default.tmp sites-enabled/default
    fi
fi

# Observability: log every authentication result so security incidents are
# auditable. auth_badpass records failed-password attempts; the password itself
# is never logged (auth_goodpass stays off).
if [[ -f "radiusd.conf" ]]; then
    sed -Ei 's/^([[:space:]]*)auth[[:space:]]*=[[:space:]]*no/\1auth = yes/' radiusd.conf
    sed -Ei 's/^([[:space:]]*)auth_badpass[[:space:]]*=[[:space:]]*no/\1auth_badpass = yes/' radiusd.conf
fi

if [[ -f "mods-available/sql" ]]; then
    if grep -qE '^\s*dialect = "mysql"' mods-available/sql; then
        echo "SQL config already substituted with mysql dialect, skipping sed pass."
    else
        echo "Updating SQL config with environment..."
        # Comment out TLS section for MySQL only when TLS is not configured.
        # If MYSQL_TLS_CA is set, keep the TLS section for secure connections.
        if [[ -z "${MYSQL_TLS_CA:-}" ]]; then
            sed -Ei '/mysql \{/,/^\t\}/ { /tls \{/,/^\t\t\}/ s/^/#/ }' mods-available/sql
        fi

        # Escape special characters in environment variables for sed
        escaped_mysql_host=$(escape_for_sed "$MYSQL_HOST")
        escaped_mysql_port=$(escape_for_sed "$MYSQL_PORT")
        escaped_mysql_user=$(escape_for_sed "$MYSQL_USER")
        escaped_mysql_password=$(escape_for_sed "$MYSQL_PASSWORD")
        escaped_mysql_dbname=$(escape_for_sed "$MYSQL_DBNAME")

        sed -Ei \
            -e "s|^([[:space:]]*)#?[[:space:]]*server[[:space:]]*=.*|\1server = \"${escaped_mysql_host}\"|" \
            -e "s|^([[:space:]]*)#?[[:space:]]*port[[:space:]]*=.*|\1port = ${escaped_mysql_port}|" \
            -e "s|^([[:space:]]*)#?[[:space:]]*login[[:space:]]*=.*|\1login = \"${escaped_mysql_user}\"|" \
            -e "s|^([[:space:]]*)#?[[:space:]]*password[[:space:]]*=.*|\1password = \"${escaped_mysql_password}\"|" \
            -e "s|dialect = \"sqlite\"|dialect = \"mysql\"|" \
            -e "s|driver = \"rlm_sql_[^\"]*\"|driver = \"rlm_sql_mysql\"|" \
            -e "s|radius_db = \"radius\"|radius_db = \"${escaped_mysql_dbname}\"|" \
            -e 's|^[[:space:]]*#[[:space:]]*read_clients = yes|        read_clients = yes|' \
            -e 's|^[[:space:]]*#[[:space:]]*client_table = "nas"|        client_table = "nas"|' \
            mods-available/sql
    fi
fi

# Only do schema import if local lock doesn't exist (expensive, one-shot).
if [[ ! -f "$LOCAL_LOCK_FILE" ]]; then

    # Database schema import with distributed locking
    if [[ -z "$DO_NOT_IMPORT_DB" ]]; then
        if schema_exists; then
            echo "Database schema already exists. Skipping import."
            run_post_schema_migrations
        else
            echo "Acquiring database lock for schema import..."
            if acquire_db_lock; then
                # Double-check after acquiring lock (another pod might have imported)
                if schema_exists; then
                    echo "Schema was imported by another instance. Skipping."
                else
                    echo "Importing default DB structure..."
                    if ! mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=10 -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" < mods-config/sql/main/mysql/schema.sql; then
                        release_db_lock
                        echo "Failed to import DB structure. Exiting..." >&2
                        exit 1
                    fi
                    echo "Database schema imported successfully."
                    run_post_schema_migrations
                fi
                release_db_lock
            else
                echo "Could not acquire lock. Checking if schema exists..."
                # Wait a bit and check if schema exists (another pod is likely importing)
                sleep 5
                if ! schema_exists; then
                    echo "Warning: Schema still doesn't exist after waiting. Continuing anyway..."
                fi
            fi
        fi
    fi

    # Redis module configuration (only when ACCT_REDIS_ENABLED=true)
    if [[ "$ACCT_REDIS_ENABLED" == "true" ]]; then
        echo "Configuring Redis accounting module..."

        # Enable redis module
        if [[ -f "mods-available/redis" ]] && [[ ! -L "mods-enabled/redis" ]]; then
            ln -sf "${RADDB_DIR}/mods-available/redis" "${RADDB_DIR}/mods-enabled/redis"
        fi

        # Configure redis module connection
        if [[ -f "mods-enabled/redis" ]]; then
            escaped_redis_host=$(escape_for_sed "$REDIS_HOST")
            escaped_redis_port=$(escape_for_sed "$REDIS_PORT")

            sed -Ei \
                -e "s|^([[:space:]]*)#?[[:space:]]*server[[:space:]]*=.*|\1server = \"${escaped_redis_host}\"|" \
                -e "s|^([[:space:]]*)#?[[:space:]]*port[[:space:]]*=.*|\1port = ${escaped_redis_port}|" \
                -e "s|^([[:space:]]*)#?[[:space:]]*database[[:space:]]*=.*|\1database = ${REDIS_DB}|" \
                mods-enabled/redis

            if [[ -n "$REDIS_PASSWORD" ]]; then
                escaped_redis_password=$(escape_for_sed "$REDIS_PASSWORD")
                sed -Ei "s|^([[:space:]]*)#?[[:space:]]*password[[:space:]]*=.*|\1password = \"${escaped_redis_password}\"|" mods-enabled/redis
            fi
        fi

        # Create custom accounting config: Interim-Update → Redis, Start/Stop → SQL
        cat > "${RADDB_DIR}/custom/acct-redis.conf" <<'ACCTEOF'
# Redis accounting for Interim-Update packets
# Format: pipe-delimited fields for flush worker parsing
# Fields: AcctUniqueId|AcctSessionId|UserName|NASIPAddress|NASPortId|EventTimestamp|
#         AcctSessionTime|AcctInputOctets|AcctOutputOctets|AcctInputGigawords|
#         AcctOutputGigawords|FramedIPAddress|FramedIPv6Address|FramedIPv6Prefix|
#         FramedInterfaceId|DelegatedIPv6Prefix
ACCTEOF

        # Patch sites-enabled/default: comment out accounting block and add Redis version
        if ! grep -q "acct-redis" "sites-enabled/default" 2>/dev/null; then
            # Add Redis accounting policy to the accounting section
            # We use unlang to route Interim-Update to Redis, everything else to SQL
            sed -Ei '/^accounting \{/,/^\}/ {
                s/^([[:space:]]*)(-?)sql$/\1# \2sql  # [redis-override] replaced by Redis accounting below/
            }' sites-enabled/default

            # Append Redis accounting logic before the closing } of accounting section
            sed -Ei '/^accounting \{/,/^\}/ {
                /^\}/ i\
\t# [acct-redis] Interim-Update → Redis buffer, Start/Stop → SQL\
\tif (&Acct-Status-Type == "Interim-Update") {\
\t\tupdate control {\
\t\t\t\&Tmp-String-0 := "%{redis:RPUSH radius:acct:interim %{Acct-Unique-Session-Id}|%{Acct-Session-Id}|%{User-Name}|%{%{NAS-IPv6-Address}:-%{NAS-IP-Address}}|%{%{NAS-Port-ID}:-%{NAS-Port}}|%{integer:Event-Timestamp}|%{Acct-Session-Time}|%{Acct-Input-Octets}|%{Acct-Output-Octets}|%{Acct-Input-Gigawords}|%{Acct-Output-Gigawords}|%{Framed-IP-Address}|%{Framed-IPv6-Address}|%{Framed-IPv6-Prefix}|%{Framed-Interface-Id}|%{Delegated-IPv6-Prefix}"\
\t\t}\
\t}\
\telse {\
\t\t-sql\
\t}
            }' sites-enabled/default
        fi

        echo "Redis accounting configured. Interim-Update → Redis, Start/Stop → SQL"
    fi

    # Escape RADIUS_SECRET for FreeRADIUS config (handles " and \ inside quoted strings)
    escaped_radius_secret=$(escape_for_freeradius_quoted "$RADIUS_SECRET")

    # Add common private network ranges for container orchestration
    # SECURITY NOTE: RADIUS_ALLOW_PRIVATE_NETWORKS=true (default) permits all RFC 1918 clients.
    # Set to "false" in production if you only need specific client CIDRs via RADIUS_CLIENTS.
    if [[ "${RADIUS_ALLOW_PRIVATE_NETWORKS:-true}" == "true" ]]; then
        if ! grep -q "client container-networks" "${RADDB_DIR}/sites-available/status" 2>/dev/null; then
            if [[ -f "sites-available/status" ]]; then
                cat <<EOT >> "${RADDB_DIR}/sites-available/status"

# Container orchestration networks (Docker/Kubernetes)
client container-networks {
    ipaddr = 10.0.0.0/8
    secret = "${escaped_radius_secret}"
}
client docker-networks {
    ipaddr = 172.16.0.0/12
    secret = "${escaped_radius_secret}"
}
client private-class-c {
    ipaddr = 192.168.0.0/16
    secret = "${escaped_radius_secret}"
}
EOT
            fi
        fi
    fi

    # Add user-defined clients from RADIUS_CLIENTS environment variable
    if [[ -n "$RADIUS_CLIENTS" ]] && [[ -f "sites-available/status" ]]; then
        echo "Adding custom RADIUS clients..."

        # Function to validate CIDR notation
        validate_cidr() {
            local cidr="$1"
            # Match IPv4 CIDR: x.x.x.x/y or just x.x.x.x
            if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
                # Validate each octet is <= 255
                IFS='/' read -r ip mask <<< "$cidr"
                IFS='.' read -r -a octets <<< "$ip"
                for octet in "${octets[@]}"; do
                    # Reject leading zeros (octal ambiguity)
                    if [[ "$octet" =~ ^0[0-9] ]]; then
                        return 1
                    fi
                    if [[ "$octet" -gt 255 ]]; then
                        return 1
                    fi
                done
                # Validate mask is <= 32 if present
                if [[ -n "$mask" ]] && [[ "$mask" -gt 32 ]]; then
                    return 1
                fi
                return 0
            fi
            return 1
        }

        IFS=',' read -ra CLIENT_ARRAY <<< "$RADIUS_CLIENTS"
        client_num=1
        for client_cidr in "${CLIENT_ARRAY[@]}"; do
            # Trim whitespace
            client_cidr=$(echo "$client_cidr" | xargs)
            if [[ -n "$client_cidr" ]]; then
                # Validate CIDR format
                if ! validate_cidr "$client_cidr"; then
                    echo "  Warning: Invalid CIDR format, skipping: $client_cidr" >&2
                    continue
                fi
                # Skip if this client already exists (idempotency)
                if grep -q "client custom-${client_num}" "${RADDB_DIR}/sites-available/status" 2>/dev/null; then
                    echo "  Client custom-${client_num} already exists, skipping."
                    ((client_num++))
                    continue
                fi
                cat <<EOT >> "${RADDB_DIR}/sites-available/status"

client custom-${client_num} {
    ipaddr = ${client_cidr}
    secret = "${escaped_radius_secret}"
}
EOT
                echo "  Added client: $client_cidr"
                ((client_num++))
            fi
        done
    fi

    touch "$LOCAL_LOCK_FILE"
    echo "Initialization complete."
else
    echo "Already initialized. Skipping config modifications."
fi

# Clean up MySQL credentials file before dropping privileges
rm -f "$MYSQL_CREDS_FILE"

# Start FreeRADIUS as freerad user (exec replaces shell, SIGTERM goes directly to freeradius)
if [[ -n "${RADIUS_DEBUG:-}" ]]; then
    echo "Starting FreeRADIUS in DEBUG mode..."
    exec gosu freerad freeradius -X
else
    echo "Starting FreeRADIUS..."
    exec gosu freerad freeradius -f
fi