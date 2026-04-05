#!/bin/bash
# FreeRADIUS Database Backup Script
set -eo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="radius_${TIMESTAMP}.sql.gz"

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

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR"

echo "=== FreeRADIUS Database Backup ==="
echo "Timestamp: $TIMESTAMP"
echo "Database: $MYSQL_DBNAME@$MYSQL_HOST:$MYSQL_PORT"
echo "Backup file: $BACKUP_FILE"
echo ""

# Perform backup
echo "Creating backup..."
TEMP_BACKUP="$BACKUP_DIR/${BACKUP_FILE}.tmp"

# Use a temporary file first to ensure atomic operation
if ! mysqldump --defaults-extra-file="$MYSQL_CREDS_FILE" \
    --connect-timeout=30 -h"$MYSQL_HOST" \
    -P"$MYSQL_PORT" \
    -u"$MYSQL_USER" \
    --single-transaction \
    --routines \
    --triggers \
    --add-drop-table \
    "$MYSQL_DBNAME" | gzip > "$TEMP_BACKUP"; then
    echo "Error: mysqldump failed" >&2
    rm -f "$TEMP_BACKUP"
    exit 1
fi

# Verify backup file is not empty and is valid gzip
if [[ ! -s "$TEMP_BACKUP" ]]; then
    echo "Error: Backup file is empty" >&2
    rm -f "$TEMP_BACKUP"
    exit 1
fi

if ! gzip -t "$TEMP_BACKUP" 2>/dev/null; then
    echo "Error: Backup file is corrupted (invalid gzip)" >&2
    rm -f "$TEMP_BACKUP"
    exit 1
fi

# Optional encryption
if [[ -n "${BACKUP_ENCRYPT_KEY:-}" ]]; then
    echo "Encrypting backup..."
    if ! gpg --batch --yes --passphrase "$BACKUP_ENCRYPT_KEY" --symmetric --cipher-algo AES256 "$TEMP_BACKUP"; then
        echo "Error: Encryption failed" >&2
        rm -f "$TEMP_BACKUP" "${TEMP_BACKUP}.gpg"
        exit 1
    fi
    rm -f "$TEMP_BACKUP"
    TEMP_BACKUP="${TEMP_BACKUP}.gpg"
    BACKUP_FILE="${BACKUP_FILE}.gpg"
fi

# Move temp file to final location (atomic on same filesystem)
mv "$TEMP_BACKUP" "$BACKUP_DIR/$BACKUP_FILE"

# Verify backup
if [[ -f "$BACKUP_DIR/$BACKUP_FILE" ]]; then
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    echo "Backup created successfully: $BACKUP_SIZE"
else
    echo "Error: Backup file not created" >&2
    exit 1
fi

# Create latest symlink (atomic operation)
ln -sf "$BACKUP_FILE" "$BACKUP_DIR/latest.sql.gz.tmp"
mv "$BACKUP_DIR/latest.sql.gz.tmp" "$BACKUP_DIR/latest.sql.gz"

# Cleanup old backups
echo ""
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "radius_*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "radius_*.sql.gz.gpg" -type f -mtime +$RETENTION_DAYS -delete
REMAINING=$(find "$BACKUP_DIR" -name "radius_*.sql.gz" -type f | wc -l)
echo "Remaining backups: $REMAINING"

# List current backups
echo ""
echo "Current backups:"
ls -lh "$BACKUP_DIR"/radius_*.sql.gz 2>/dev/null || echo "No backups found"

echo ""
echo "=== Backup Complete ==="
