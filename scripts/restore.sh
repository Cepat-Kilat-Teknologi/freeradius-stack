#!/bin/bash
# FreeRADIUS Database Restore Script
set -eo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_FILE="${1:-latest.sql.gz}"

# Validate required environment variables
for var in MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD MYSQL_DBNAME; do
    if [[ -z "${!var}" ]]; then
        echo "Error: $var is not set" >&2
        exit 1
    fi
done

# Create MySQL credentials file to avoid deprecated MYSQL_PWD env var
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
trap 'rm -f "$MYSQL_CREDS_FILE"' EXIT

# Resolve backup file path
if [[ "$BACKUP_FILE" != /* ]]; then
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
fi

# Check if backup file exists
if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Error: Backup file not found: $BACKUP_FILE" >&2
    echo ""
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/radius_*.sql.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

echo "=== FreeRADIUS Database Restore ==="
echo "Database: $MYSQL_DBNAME@$MYSQL_HOST:$MYSQL_PORT"
echo "Backup file: $BACKUP_FILE"
echo ""

# Confirm restore
if [[ -t 0 ]]; then
    read -p "WARNING: This will overwrite the current database. Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Restore cancelled."
        exit 0
    fi
elif [[ "${1:-}" != "--force" ]] && [[ "${2:-}" != "--force" ]]; then
    echo "Error: Non-interactive mode requires --force flag" >&2
    exit 1
fi

# Verify backup file integrity before restore
if [[ "$BACKUP_FILE" == *.gz ]]; then
    echo "Verifying backup file integrity..."
    if ! gzip -t "$BACKUP_FILE" 2>/dev/null; then
        echo "Error: Backup file is corrupted (invalid gzip)" >&2
        exit 1
    fi
    echo "Backup file integrity verified."
fi

# Perform restore
echo "Restoring database..."
if [[ "$BACKUP_FILE" == *.gz ]]; then
    if ! gunzip -c "$BACKUP_FILE" | mysql --defaults-extra-file="$MYSQL_CREDS_FILE" \
        --connect-timeout=30 -h"$MYSQL_HOST" \
        -P"$MYSQL_PORT" \
        -u"$MYSQL_USER" \
        "$MYSQL_DBNAME"; then
        echo "Error: Database restore failed" >&2
        exit 1
    fi
else
    if ! mysql --defaults-extra-file="$MYSQL_CREDS_FILE" \
        --connect-timeout=30 -h"$MYSQL_HOST" \
        -P"$MYSQL_PORT" \
        -u"$MYSQL_USER" \
        "$MYSQL_DBNAME" < "$BACKUP_FILE"; then
        echo "Error: Database restore failed" >&2
        exit 1
    fi
fi

echo ""
echo "=== Restore Complete ==="
echo "Database restored from: $BACKUP_FILE"
