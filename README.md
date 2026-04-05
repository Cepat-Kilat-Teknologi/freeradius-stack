# FreeRADIUS Stack

Production-ready FreeRADIUS deployment with MySQL backend. Supports Docker Compose, Kubernetes, and Helm.

## Features

- **FreeRADIUS 3.2.8** with MySQL/MariaDB backend (Debian Trixie base, FreeRADIUS from sid)
- **Multi-platform** Docker images (linux/amd64, linux/arm64)
- **Multiple deployment options**: Docker Compose, Kubernetes manifests, Helm chart
- **High Availability** ready with external MySQL cluster support
- **Auto-initialization** of database schema
- **Configurable RADIUS clients** via environment variables
- **Health checks** for container orchestration
- **Log rotation** to prevent disk bloat
- **CI/CD** with GitHub Actions
- **Security hardened** containers (non-root, capability drop, no-new-privileges)
- **NetworkPolicy** for pod traffic isolation
- **MySQL TLS** support for encrypted database connections
- **Backup encryption** with GPG
- **Debug mode** via environment variable
- **MariaDB support** as alternative database
- **Vulnerability scanning** in CI pipeline

## Docker Images

| Registry | Image |
|----------|-------|
| Docker Hub | `cepatkilatteknologi/freeradius:3.2.8` |
| GHCR | `ghcr.io/cepat-kilat-teknologi/freeradius:3.2.8` |

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
# For local development (faster startup ~90s)
helm install freeradius examples/helm/freeradius \
  -f examples/helm/freeradius/values-local.yaml \
  --namespace freeradius \
  --create-namespace

# For production with bundled MySQL
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

#### Helm Chart Features

- **`existingSecret`** support for external secret management (e.g., Sealed Secrets, External Secrets Operator)
- **HPA (autoscaling)** support for automatic replica scaling based on CPU/memory
- **ServiceMonitor** for Prometheus metrics collection
- **NetworkPolicy** template for pod traffic isolation
- **Helm tests** -- validate deployment with `helm test freeradius`
- **`imagePullSecrets`** for pulling from private container registries

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
    │   ├── kustomization.yaml
    │   ├── networkpolicy.yaml
    │   └── pdb.yaml
    └── helm/freeradius/          # Helm chart
        ├── Chart.yaml
        ├── .helmignore
        ├── values.yaml            # Production values
        ├── values-local.yaml      # Local development (faster)
        └── templates/
            ├── NOTES.txt
            ├── hpa.yaml
            ├── networkpolicy.yaml
            ├── servicemonitor.yaml
            └── tests/
```

## Configuration

### Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `MYSQL_HOST` | MySQL server hostname | Yes | - |
| `MYSQL_PORT` | MySQL server port (numeric only) | Yes | - |
| `MYSQL_USER` | MySQL username | Yes | - |
| `MYSQL_PASSWORD` | MySQL password | Yes | - |
| `MYSQL_DBNAME` | MySQL database name (alphanumeric + underscore only) | Yes | - |
| `RADIUS_SECRET` | RADIUS shared secret (special characters supported) | Yes | - |
| `RADIUS_CLIENTS` | Additional clients (comma-separated CIDR, validated) | No | - |
| `TZ` | Timezone (e.g., `Asia/Jakarta`) | No | `UTC` |
| `DO_NOT_IMPORT_DB` | Skip DB schema import if set | No | - |
| `HEALTHCHECK_SECRET` | Secret for internal health checks (localhost only) | No | `testing123` |
| `RADIUS_ALLOW_PRIVATE_NETWORKS` | Add RFC 1918 ranges as RADIUS clients | No | `true` |
| `RADIUS_DEBUG` | Enable FreeRADIUS debug mode (-X) | No | - |
| `MYSQL_TLS_CA` | Path to MySQL CA certificate | No | - |
| `MYSQL_TLS_CERT` | Path to MySQL client certificate | No | - |
| `MYSQL_TLS_KEY` | Path to MySQL client key | No | - |
| `BACKUP_ENCRYPT_KEY` | GPG passphrase for backup encryption | No | - |
| `DB_IMAGE` | Database image (Docker Compose) | No | `mysql:8.4` |
| `FREERADIUS_IMAGE` | FreeRADIUS image override (Docker Compose) | No | `cepatkilatteknologi/freeradius:3.2.8` |

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
| 18121 | UDP | Status Server (localhost only, not exposed in Dockerfile) |

## Commands

### Root Makefile

```bash
make help              # Show all commands

# Image
make build             # Build Docker image
make push REGISTRY=x   # Push to registry
make build-multiarch   # Build multi-arch image (amd64+arm64)
make push-multiarch    # Build and push multi-arch image

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
make backup            # Backup database
make restore FILE=x    # Restore from backup
make list-backups      # List available backups
make clean             # Remove everything
```

## Testing

### Test RADIUS Authentication

```bash
# Using radtest (install freeradius-utils)
radtest username password localhost 1812 YOUR_SECRET

# From container
docker exec freeradius sh -c 'echo "User-Name=testuser,User-Password=testpass" | radclient 127.0.0.1:1812 auth testing123'
```

### Test Status Server

```bash
# From container (uses HEALTHCHECK_SECRET environment variable)
docker exec freeradius sh -c \
  'echo "Message-Authenticator = 0x00" | radclient 127.0.0.1:18121 status $HEALTHCHECK_SECRET'
```

## Backup & Restore

### Create Backup

```bash
cd examples/docker

# Create a timestamped backup
make backup
# Creates: backups/radius_YYYYMMDD_HHMMSS.sql.gz

# Create an encrypted backup (set BACKUP_ENCRYPT_KEY in .env)
BACKUP_ENCRYPT_KEY=my-secret-passphrase make backup
# Creates: backups/radius_YYYYMMDD_HHMMSS.sql.gz.gpg

# List available backups
make list-backups
```

### Restore from Backup

```bash
# Restore a specific backup (use --force for non-interactive mode)
make restore FILE=backups/radius_20260127_120000.sql.gz
make restore FILE=backups/radius_20260127_120000.sql.gz --force

# Verify restore was successful
make test-auth
```

### Manual Backup Commands

```bash
# Backup
docker compose exec -T db mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" \
  --single-transaction --routines --triggers radius | gzip > backup.sql.gz

# Restore
gunzip -c backup.sql.gz | docker compose exec -T db mysql -uroot -p"$MYSQL_ROOT_PASSWORD" radius
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

### Resilience & Auto-scaling

- **PodDisruptionBudget** ensures minimum 1 replica remains available during maintenance or node drains
- **topologySpreadConstraints** spread pods across nodes for fault tolerance
- **HPA (Horizontal Pod Autoscaler)** for automatic scaling based on CPU/memory utilization

## CI/CD

### GitHub Actions

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `ci.yml` | Push to main, tags, PRs | Build, test, scan & push Docker images |
| `helm.yml` | Changes to `examples/helm/` | Publish Helm chart |

The CI pipeline includes Trivy vulnerability scanning, an automated test job, and FreeRADIUS version auto-detection from the built image.

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

### Debug Mode

Enable debug mode via the `RADIUS_DEBUG` environment variable to start FreeRADIUS with full debug output (`-X`):

```bash
# Enable debug mode with docker run
docker run -e RADIUS_DEBUG=1 cepatkilatteknologi/freeradius:3.2.8

# Or in docker-compose, add to .env:
RADIUS_DEBUG=1
```

### FreeRADIUS won't start

```bash
# Check logs
docker logs freeradius

# Run in debug mode
docker exec -it freeradius freeradius -X
```

### Can't connect to MySQL

```bash
# Verify MySQL is running
docker exec freeradius mysql --skip-ssl -h db -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SELECT 1"

# Check environment variables
docker exec freeradius env | grep MYSQL
```

### Authentication failing

```bash
# Check user exists
docker exec radius-mysql mysql -u radius -p$MYSQL_PASSWORD radius \
  -e "SELECT * FROM radcheck WHERE username='testuser';"

# Check RADIUS debug
docker exec freeradius freeradius -X
# Then try authentication and watch the output
```

### Authentication failing with special characters in secret

If your `RADIUS_SECRET` contains special characters (e.g., `/`, `+`, `=` from base64), ensure you're using the latest image version. Earlier versions had a bug where special characters were incorrectly escaped.

```bash
# Verify the secret in FreeRADIUS config matches your RADIUS_SECRET
docker exec freeradius grep -A2 "client container-networks" /etc/freeradius/3.0/sites-enabled/status

# The secret should match RADIUS_SECRET exactly, without backslash escaping
```

### Health check failing

```bash
# Test status server manually
docker exec freeradius sh -c 'echo "Message-Authenticator = 0x00" | radclient -t 3 127.0.0.1:18121 status $HEALTHCHECK_SECRET'
```

## Security Considerations

### Required Before Production

1. **Change all default secrets** - All `CHANGE_ME_*` values MUST be replaced with strong, randomly generated secrets:
   ```bash
   # Generate secure passwords
   openssl rand -base64 32
   ```

2. **CHANGE_ME_* values are rejected** -- the entrypoint will fail on startup if any placeholder `CHANGE_ME_*` values remain in the configuration

3. **Use strong passwords** - MySQL and RADIUS secrets should be at least 32 characters. Special characters (including `/`, `+`, `=` from base64) are fully supported

4. **Validate input** - The entrypoint script validates:
   - `MYSQL_DBNAME`: Only alphanumeric and underscore allowed
   - `MYSQL_PORT`: Must be numeric
   - `RADIUS_CLIENTS`: Must be valid CIDR notation

### Network Security

5. **Restrict network access** to RADIUS ports (1812, 1813):
   - Use firewall rules to allow only trusted NAS devices
   - For Kubernetes, use NetworkPolicies
   - For cloud LoadBalancers, use internal LB annotations:
     ```yaml
     # GKE
     annotations:
       networking.gke.io/load-balancer-type: "Internal"
     ```
     ```yaml
     # AWS
     annotations:
       service.beta.kubernetes.io/aws-load-balancer-internal: "true"
     ```

6. **NetworkPolicy** restricts MySQL access to FreeRADIUS and backup pods only

7. **Pod Security Standards** labels enforce baseline policy on the namespace

8. **Status server (18121)** is bound to localhost by default and is **no longer exposed** in the Dockerfile -- used only for internal health checks

### Database Security

9. **MySQL TLS** supported for encrypted database traffic -- configure via `MYSQL_TLS_CA`, `MYSQL_TLS_CERT`, and `MYSQL_TLS_KEY` environment variables

10. **Backup encryption** available via `BACKUP_ENCRYPT_KEY` for GPG-encrypted backups

11. **Backup security** - Backup files contain sensitive data, secure the backup storage

### Container Security

12. Container runs as **non-root** (freerad user via gosu)

13. **Container capabilities** are dropped (only SETUID, SETGID, NET_BIND_SERVICE retained)

14. **Security contexts** - Helm chart includes:
    - Pod anti-affinity for high availability
    - Dropped capabilities (only SETUID, SETGID, NET_BIND_SERVICE)
    - No privilege escalation (`no-new-privileges`)

15. **Regular updates** - Rebuild images periodically for security patches

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
