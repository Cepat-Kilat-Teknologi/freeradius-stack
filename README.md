# FreeRADIUS Stack

Production-ready FreeRADIUS deployment with MySQL backend. Supports Docker Compose, Kubernetes, and Helm.

## Features

- **FreeRADIUS 3.2.8** (latest stable) with MySQL/MariaDB backend
- **Multi-platform** Docker images (amd64, arm64)
- **Multiple deployment options**: Docker Compose, Kubernetes manifests, Helm chart
- **High Availability** ready with external MySQL cluster support
- **Auto-initialization** of database schema
- **Configurable RADIUS clients** via environment variables
- **Health checks** for container orchestration
- **Log rotation** to prevent disk bloat
- **CI/CD** with GitHub Actions

## Quick Start

### Docker Compose (Local Development)

```bash
cd examples/docker

# Create environment file
cp .env.example .env

# Edit .env - change all CHANGE_ME_* values
nano .env

# Start services
make pull && make up

# Check status
make status

# Add test user and test
make add-test-user
make test-auth
```

### Kubernetes

```bash
# Edit secrets first
nano examples/kubernetes/secret.yaml

# Apply manifests
make k8s-apply

# Check status
make k8s-status
```

### Helm

```bash
# Install with bundled MySQL
helm install freeradius examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set freeradius.secret=YOUR_RADIUS_SECRET \
  --set mysql.rootPassword=YOUR_ROOT_PASSWORD \
  --set mysql.password=YOUR_DB_PASSWORD

# Or with external MySQL cluster
helm install freeradius examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set mysql.enabled=false \
  --set externalMysql.host=mysql-cluster.example.com \
  --set externalMysql.password=YOUR_DB_PASSWORD \
  --set freeradius.secret=YOUR_RADIUS_SECRET
```

## Project Structure

```
freeradius-stack/
├── Dockerfile                    # FreeRADIUS image
├── Makefile                      # Root commands
├── scripts/
│   ├── entrypoint.sh             # Container entrypoint
│   └── setup-gh-pages.sh         # Helm repo setup
├── .github/workflows/
│   ├── ci.yml                    # Build & push images
│   └── helm.yml                  # Publish Helm chart
└── examples/
    ├── docker/                   # Docker Compose
    │   ├── docker-compose.yaml
    │   ├── .env.example
    │   └── Makefile
    ├── kubernetes/               # K8s manifests
    │   ├── namespace.yaml
    │   ├── secret.yaml
    │   ├── configmap.yaml
    │   ├── mysql-statefulset.yaml
    │   ├── freeradius-deployment.yaml
    │   └── kustomization.yaml
    └── helm/freeradius/          # Helm chart
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `MYSQL_HOST` | MySQL server hostname | Yes |
| `MYSQL_PORT` | MySQL server port | Yes |
| `MYSQL_USER` | MySQL username | Yes |
| `MYSQL_PASSWORD` | MySQL password | Yes |
| `MYSQL_DBNAME` | MySQL database name | Yes |
| `RADIUS_SECRET` | RADIUS shared secret | Yes |
| `RADIUS_CLIENTS` | Additional clients (comma-separated CIDR) | No |
| `TZ` | Timezone (e.g., `Asia/Jakarta`) | No |
| `DO_NOT_IMPORT_DB` | Skip DB schema import if set | No |
| `HEALTHCHECK_SECRET` | Secret for internal health checks (localhost only) | No |

### Adding RADIUS Clients

Via environment variable:
```bash
RADIUS_CLIENTS=10.0.0.0/8,192.168.0.0/16,203.0.113.50/32
```

Via database (NAS table):
```
INSERT INTO nas (nasname, shortname, secret, description)
VALUES ('192.168.1.1', 'router1', 'secret123', 'Main Router');
```

### Adding Users

```
-- Simple user with password
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('john', 'Cleartext-Password', ':=', 'password123');

-- User with VLAN assignment
INSERT INTO radreply (username, attribute, op, value)
VALUES ('john', 'Tunnel-Type', ':=', 'VLAN'),
       ('john', 'Tunnel-Medium-Type', ':=', 'IEEE-802'),
       ('john', 'Tunnel-Private-Group-ID', ':=', '100');
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 1812 | UDP | RADIUS Authentication |
| 1813 | UDP | RADIUS Accounting |
| 18121 | UDP | Status Server (monitoring) |

## Commands

### Root Makefile

```bash
make help              # Show all commands

# Image
make build             # Build Docker image
make push REGISTRY=x   # Push to registry

# Docker Compose
make docker-up         # Start services
make docker-down       # Stop services
make docker-logs       # View logs

# Kubernetes
make k8s-apply         # Apply manifests
make k8s-delete        # Delete resources
make k8s-status        # Show status

# Helm
make helm-install      # Install chart
make helm-upgrade      # Upgrade release
make helm-uninstall    # Uninstall
make helm-template     # Render templates
```

### Docker Compose (examples/docker/)

```bash
make init-env          # Create .env file
make pull              # Pull images
make up                # Start services
make down              # Stop services
make logs              # View logs
make status            # Show status
make mysql             # Connect to MySQL
make add-test-user     # Add test user
make test-auth         # Test authentication
make clean             # Remove everything
```

## Testing

### Test RADIUS Authentication

```bash
# Using radtest (install freeradius-utils)
radtest username password localhost 1812 YOUR_SECRET

# From container
docker exec freeradius radtest testuser testpass localhost 0 YOUR_SECRET
```

### Test Status Server

```bash
# From container (uses HEALTHCHECK_SECRET environment variable)
docker exec freeradius sh -c \
  'echo "Message-Authenticator = 0x00" | radclient 127.0.0.1:18121 status $HEALTHCHECK_SECRET'
```

## High Availability

### External MySQL Cluster

For production, use an external MySQL cluster:

**Docker Compose:**
```yaml
# Remove db service, update freeradius environment
environment:
  MYSQL_HOST: mysql-cluster.example.com
  MYSQL_PORT: 3306
```

**Helm:**
```bash
helm install freeradius examples/helm/freeradius \
  --set mysql.enabled=false \
  --set externalMysql.host=mysql-cluster.example.com \
  --set externalMysql.password=PASSWORD
```

### Multiple FreeRADIUS Replicas

Helm chart supports multiple replicas:
```yaml
freeradius:
  replicaCount: 3
```

All replicas share the same MySQL database for user/NAS data.

## CI/CD

### GitHub Actions

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `ci.yml` | Push to main, tags | Build & push Docker images |
| `helm.yml` | Changes to `examples/helm/` | Publish Helm chart |

### Required Secrets

| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

### Docker Images

After CI runs, images are available at:
- Docker Hub: `docker.io/cepatkilatteknologi/freeradius:VERSION`
- GHCR: `ghcr.io/cepat-kilat-teknologi/freeradius:VERSION`

### Helm Repository

After setting up GitHub Pages:
```bash
helm repo add freeradius https://cepat-kilat-teknologi.github.io/freeradius-stack
helm repo update
helm install freeradius freeradius/freeradius
```

## Troubleshooting

### FreeRADIUS won't start

```bash
# Check logs
docker logs freeradius

# Run in debug mode
docker exec -it freeradius radiusd -X
```

### Can't connect to MySQL

```bash
# Verify MySQL is running
docker exec freeradius mysqladmin -h$MYSQL_HOST -u$MYSQL_USER -p ping

# Check environment variables
docker exec freeradius env | grep MYSQL
```

### Authentication failing

```bash
# Check user exists
docker exec radius-mysql mysql -uroot -p radius \
  -e "SELECT * FROM radcheck WHERE username='testuser';"

# Check RADIUS debug
docker exec freeradius radiusd -X
# Then try authentication and watch the output
```

### Health check failing

```bash
# Test status server manually (uses HEALTHCHECK_SECRET)
docker exec freeradius sh -c 'radclient -t 3 127.0.0.1:18121 status $HEALTHCHECK_SECRET'
```

## Security Considerations

1. **Change all default secrets** before production deployment
2. **Use strong passwords** for MySQL and RADIUS secrets
3. **Restrict network access** to RADIUS ports (1812, 1813)
4. **Status server (18121)** is bound to localhost by default
5. **Use TLS** for MySQL connections in production
6. **Regular updates** - rebuild images periodically for security patches

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## Links

- [FreeRADIUS Documentation](https://freeradius.org/documentation/)
- [FreeRADIUS Wiki](https://wiki.freeradius.org/)
- [MySQL Schema Reference](https://wiki.freeradius.org/guide/SQL-HOWTO)
