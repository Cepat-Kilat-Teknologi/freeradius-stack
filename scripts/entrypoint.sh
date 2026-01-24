#!/bin/bash
set -e

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

echo "Starting FreeRADIUS initialization..."

# Wait for MySQL with proper timeout handling
echo "Waiting for MySQL to be ready..."
mysql_ready=false
for i in {1..30}; do
    if MYSQL_PWD="$MYSQL_PASSWORD" mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -e "SELECT 1" &>/dev/null; then
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

# Use persistent lock file location
LOCK_FILE="/etc/freeradius/3.0/custom/init.lock"

if [[ ! -f "$LOCK_FILE" ]]; then
    cd /etc/freeradius/3.0 || { echo "Failed to cd /etc/freeradius/3.0"; exit 1; }

    if [[ -z "$DO_NOT_IMPORT_DB" ]]; then
        echo "Importing default DB structure..."
        if ! MYSQL_PWD="$MYSQL_PASSWORD" mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" < mods-config/sql/main/mysql/schema.sql; then
            echo "Failed to import DB structure. Exiting..." >&2
            exit 1
        fi
    fi

    echo "Enabling SQL module in sites-enabled/default..."
    sed -Ei 's/#[\t ]*sql$/sql/g' sites-enabled/default

    echo "Updating SQL config with environment..."
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

    echo "Enabling Status Server..."
    ln -sf /etc/freeradius/3.0/sites-available/status /etc/freeradius/3.0/sites-enabled/status

    # Add localhost client for internal healthcheck (fixed secret for Docker healthcheck)
    cat <<'EOT' >> /etc/freeradius/3.0/sites-available/status

# Internal healthcheck client (localhost only)
client localhost-healthcheck {
    ipaddr = 127.0.0.1
    secret = testing123
}
EOT

    # Add Docker network client for internal communication
    cat <<EOT >> /etc/freeradius/3.0/sites-available/status

# Docker internal network
client docker-internal {
    ipaddr = 172.16.0.0/12
    secret = ${RADIUS_SECRET}
}
EOT

    # Add user-defined clients from RADIUS_CLIENTS environment variable
    if [[ -n "$RADIUS_CLIENTS" ]]; then
        echo "Adding custom RADIUS clients..."
        IFS=',' read -ra CLIENT_ARRAY <<< "$RADIUS_CLIENTS"
        client_num=1
        for client_cidr in "${CLIENT_ARRAY[@]}"; do
            # Trim whitespace
            client_cidr=$(echo "$client_cidr" | xargs)
            if [[ -n "$client_cidr" ]]; then
                cat <<EOT >> /etc/freeradius/3.0/sites-available/status

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

    touch "$LOCK_FILE"
    echo "Initialization complete."
else
    echo "Already initialized. Skipping DB import and config."
fi

echo "Starting FreeRADIUS..."
exec freeradius -f