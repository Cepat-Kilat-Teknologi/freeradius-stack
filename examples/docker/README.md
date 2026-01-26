# Docker Compose Deployment

Run FreeRADIUS with MySQL locally using Docker Compose.

## Quick Start

```bash
# 1. Create .env file
make init-env

# 2. Edit .env - change all CHANGE_ME_* values
nano .env

# 3. Pull and start
make pull
make up

# 4. Check status
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

# RADIUS
RADIUS_SECRET=your-radius-secret

# Optional: Additional clients
RADIUS_CLIENTS=10.0.0.0/8,192.168.0.0/16

# Timezone
TZ=Asia/Jakarta
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 1812 | UDP | RADIUS Authentication |
| 1813 | UDP | RADIUS Accounting |
| 18121 | UDP | Status Server (localhost only) |
