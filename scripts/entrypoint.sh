#!/bin/bash
set -e

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

# Set timezone if provided
if [[ -n "$TZ" ]]; then
    ln -fs /usr/share/zoneinfo/"$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

echo "Starting FreeRADIUS 3.2.8 initialization..."

# Wait for MySQL with proper timeout handling
echo "Waiting for MySQL to be ready..."
mysql_ready=false
for i in {1..30}; do
    if MYSQL_PWD="$MYSQL_PASSWORD" mysql --skip-ssl -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -e "SELECT 1" &>/dev/null; then
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

# Function to check if schema already exists
schema_exists() {
    local table_count
    table_count=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql --skip-ssl -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DBNAME' AND table_name='radcheck';" 2>/dev/null || echo "0")
    [[ "$table_count" -gt 0 ]]
}

# Function to acquire lock using MySQL (works across pods)
acquire_db_lock() {
    local lock_name="freeradius_init_lock"
    local lock_timeout=30
    local result
    result=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql --skip-ssl -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" -N -e "SELECT GET_LOCK('$lock_name', $lock_timeout);" 2>/dev/null || echo "0")
    [[ "$result" == "1" ]]
}

# Function to release lock
release_db_lock() {
    local lock_name="freeradius_init_lock"
    MYSQL_PWD="$MYSQL_PASSWORD" mysql --skip-ssl -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" -N -e "SELECT RELEASE_LOCK('$lock_name');" &>/dev/null || true
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

# Always update admin client secret to match HEALTHCHECK_SECRET for healthcheck to work
healthcheck_secret="${HEALTHCHECK_SECRET:-testing123}"
if [[ -f "sites-available/status" ]]; then
    echo "Updating status server admin secret..."
    sed -Ei "/client admin/,/\}/s/secret = .*/secret = ${healthcheck_secret}/" "sites-available/status"
fi

# Only do full initialization if local lock doesn't exist
if [[ ! -f "$LOCAL_LOCK_FILE" ]]; then

    # Database schema import with distributed locking
    if [[ -z "$DO_NOT_IMPORT_DB" ]]; then
        if schema_exists; then
            echo "Database schema already exists. Skipping import."
        else
            echo "Acquiring database lock for schema import..."
            if acquire_db_lock; then
                # Double-check after acquiring lock (another pod might have imported)
                if schema_exists; then
                    echo "Schema was imported by another instance. Skipping."
                else
                    echo "Importing default DB structure..."
                    if ! MYSQL_PWD="$MYSQL_PASSWORD" mysql --skip-ssl -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" < mods-config/sql/main/mysql/schema.sql; then
                        release_db_lock
                        echo "Failed to import DB structure. Exiting..." >&2
                        exit 1
                    fi
                    echo "Database schema imported successfully."
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

    echo "Enabling SQL module in sites-enabled/default..."
    if [[ -f "sites-enabled/default" ]]; then
        sed -Ei 's/#[\t ]*sql$/sql/g' sites-enabled/default
    fi

    echo "Updating SQL config with environment..."
    if [[ -f "mods-enabled/sql" ]]; then
        # Comment out TLS section for MySQL (lines containing tls { to closing })
        # This is needed because the CA cert path doesn't exist
        sed -Ei '/mysql \{/,/^\t\}/ { /tls \{/,/^\t\t\}/ s/^/#/ }' mods-enabled/sql

        sed -Ei \
            -e "s|^([[:space:]]*)#?[[:space:]]*server[[:space:]]*=.*|\1server = \"$MYSQL_HOST\"|" \
            -e "s|^([[:space:]]*)#?[[:space:]]*port[[:space:]]*=.*|\1port = $MYSQL_PORT|" \
            -e "s|^([[:space:]]*)#?[[:space:]]*login[[:space:]]*=.*|\1login = \"$MYSQL_USER\"|" \
            -e "s|^([[:space:]]*)#?[[:space:]]*password[[:space:]]*=.*|\1password = \"$MYSQL_PASSWORD\"|" \
            -e "s|dialect = \"sqlite\"|dialect = \"mysql\"|" \
            -e "s|driver = \"rlm_sql_[^\"]*\"|driver = \"rlm_sql_mysql\"|" \
            -e "s|radius_db = \"radius\"|radius_db = \"$MYSQL_DBNAME\"|" \
            -e 's|^[[:space:]]*#[[:space:]]*read_clients = yes|        read_clients = yes|' \
            -e 's|^[[:space:]]*#[[:space:]]*client_table = "nas"|        client_table = "nas"|' \
            mods-enabled/sql
    fi

    # Add common private network ranges for container orchestration
    if [[ -f "sites-available/status" ]]; then
        cat <<EOT >> "${RADDB_DIR}/sites-available/status"

# Container orchestration networks (Docker/Kubernetes)
client container-networks {
    ipaddr = 10.0.0.0/8
    secret = ${RADIUS_SECRET}
}
client docker-networks {
    ipaddr = 172.16.0.0/12
    secret = ${RADIUS_SECRET}
}
client private-class-c {
    ipaddr = 192.168.0.0/16
    secret = ${RADIUS_SECRET}
}
EOT
    fi

    # Add user-defined clients from RADIUS_CLIENTS environment variable
    if [[ -n "$RADIUS_CLIENTS" ]] && [[ -f "sites-available/status" ]]; then
        echo "Adding custom RADIUS clients..."
        IFS=',' read -ra CLIENT_ARRAY <<< "$RADIUS_CLIENTS"
        client_num=1
        for client_cidr in "${CLIENT_ARRAY[@]}"; do
            # Trim whitespace
            client_cidr=$(echo "$client_cidr" | xargs)
            if [[ -n "$client_cidr" ]]; then
                cat <<EOT >> "${RADDB_DIR}/sites-available/status"

client custom-${client_num} {
    ipaddr = ${client_cidr}
    secret = ${RADIUS_SECRET}
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

# Trap signals for graceful shutdown
trap 'echo "Received shutdown signal, stopping FreeRADIUS..."; kill -TERM "$child" 2>/dev/null; wait "$child"' SIGTERM SIGINT

echo "Starting FreeRADIUS 3.2.8..."
freeradius -f &
child=$!
wait "$child"