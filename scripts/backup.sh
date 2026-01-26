#!/bin/bash
# FreeRADIUS Database Backup Script
set -e

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

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR"

echo "=== FreeRADIUS Database Backup ==="
echo "Timestamp: $TIMESTAMP"
echo "Database: $MYSQL_DBNAME@$MYSQL_HOST:$MYSQL_PORT"
echo "Backup file: $BACKUP_FILE"
echo ""

# Perform backup
echo "Creating backup..."
MYSQL_PWD="$MYSQL_PASSWORD" mysqldump \
    -h"$MYSQL_HOST" \
    -P"$MYSQL_PORT" \
    -u"$MYSQL_USER" \
    --single-transaction \
    --routines \
    --triggers \
    --add-drop-table \
    "$MYSQL_DBNAME" | gzip > "$BACKUP_DIR/$BACKUP_FILE"

# Verify backup
if [[ -f "$BACKUP_DIR/$BACKUP_FILE" ]]; then
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    echo "Backup created successfully: $BACKUP_SIZE"
else
    echo "Error: Backup file not created" >&2
    exit 1
fi

# Create latest symlink
ln -sf "$BACKUP_FILE" "$BACKUP_DIR/latest.sql.gz"

# Cleanup old backups
echo ""
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "radius_*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete
REMAINING=$(find "$BACKUP_DIR" -name "radius_*.sql.gz" -type f | wc -l)
echo "Remaining backups: $REMAINING"

# List current backups
echo ""
echo "Current backups:"
ls -lh "$BACKUP_DIR"/radius_*.sql.gz 2>/dev/null || echo "No backups found"

echo ""
echo "=== Backup Complete ==="
