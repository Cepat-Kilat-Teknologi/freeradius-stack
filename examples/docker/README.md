# Docker Compose Deployment

Run FreeRADIUS with MySQL locally using Docker Compose.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose v2+

## Quick Start

```bash
# 1. Create .env file from template
make init-env

# 2. Edit .env - IMPORTANT: change all CHANGE_ME_* values
nano .env

# 3. Pull images and start services
make pull
make up

# 4. Wait for services to be ready, then check status
make status
make logs
```

## Commands

| Command | Description |
|---------|-------------|
| `make init-env` | Create .env from template |
| `make pull` | Pull latest images |
| `make up` | Start services |
| `make down` | Stop services |
| `make logs` | View logs |
| `make status` | Show container status |
| `make clean` | Remove containers and volumes |
| `make mysql` | Connect to MySQL |
| `make test-auth` | Test RADIUS authentication |
| `make add-test-user` | Add test user |

## Testing

```bash
# Add a test user
make add-test-user

# Test authentication
make test-auth

# Or manually:
radtest testuser testpass localhost 1812 YOUR_SECRET
```

## Configuration

Edit `.env` file:

```bash
# MySQL
MYSQL_USER=radius
MYSQL_PASSWORD=your-secure-password
MYSQL_ROOT_PASSWORD=your-root-password
MYSQL_DBNAME=radius

# Database image (default: mysql:8.4, alternative: mariadb:11)
DB_IMAGE=mysql:8.4

# MySQL TLS (optional)
# MYSQL_TLS_CA=/path/to/ca.pem
# MYSQL_TLS_CERT=/path/to/client-cert.pem
# MYSQL_TLS_KEY=/path/to/client-key.pem

# RADIUS
RADIUS_SECRET=your-radius-secret

# Optional: Additional clients
RADIUS_CLIENTS=10.0.0.0/8,192.168.0.0/16

# Private network RADIUS clients (default: true)
RADIUS_ALLOW_PRIVATE_NETWORKS=true

# Debug mode (set to enable FreeRADIUS -X output)
# RADIUS_DEBUG=1

# Backup encryption (optional GPG passphrase)
# BACKUP_ENCRYPT_KEY=your-passphrase

# Timezone
TZ=Asia/Jakarta
```

## MariaDB Support

To use MariaDB instead of MySQL:

```bash
# Use MariaDB instead of MySQL
# Edit .env and change:
DB_IMAGE=mariadb:11
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 1812 | UDP | RADIUS Authentication |
| 1813 | UDP | RADIUS Accounting |
| 18121 | UDP | Status Server (localhost only) |

## Backup & Restore

```bash
# Create backup
make backup

# Create encrypted backup
BACKUP_ENCRYPT_KEY=your-passphrase make backup
# Encrypted backups produce .sql.gz.gpg files

# List available backups
make list-backups

# Restore from backup
make restore FILE=backups/radius_20260127_120000.sql.gz

# Non-interactive restore (e.g., in scripts)
# Restore now requires confirmation. For automation, use --force flag directly:
docker compose exec -T db bash -c 'gunzip -c /backups/file.sql.gz | mysql ...'
```

Backups are stored in the `backups/` directory with automatic retention cleanup.

## Troubleshooting

### Services won't start

```bash
# Check logs
make logs

# Verify .env file exists and has correct values
cat .env
```

### Authentication failing

```bash
# Verify user exists
make mysql
# Then run: SELECT * FROM radcheck WHERE username='testuser';

# Check FreeRADIUS logs
docker compose logs freeradius
```

### Health check failing

```bash
# Test status server manually
docker compose exec freeradius sh -c \
  'echo "Message-Authenticator = 0x00" | radclient -t 3 127.0.0.1:18121 status $HEALTHCHECK_SECRET'
```

### Debug Mode

```bash
# Enable debug mode for verbose FreeRADIUS output
# Add to .env:
RADIUS_DEBUG=1

# Then restart:
make down && make up
make logs
```

## Security Notes

- Change all `CHANGE_ME_*` values in `.env` before use
- `CHANGE_ME_*` placeholder values are rejected at startup
- The `.env` file is excluded from git (see `.gitignore`)
- Use strong, randomly generated passwords (special characters like `/`, `+`, `=` are supported)
- RADIUS_CLIENTS are validated for proper CIDR format
- Container runs as non-root (`freerad` user)
- Capabilities are dropped (only `SETUID`, `SETGID`, `NET_BIND_SERVICE` retained)
- `no-new-privileges` security option enabled
- MySQL TLS available for encrypted database connections
