# FreeRADIUS Helm Chart

Helm chart for deploying FreeRADIUS with MySQL backend on Kubernetes.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.x
- FreeRADIUS image available in a registry

## Installation

### Quick Start (with bundled MySQL)

```bash
# From repository root
helm install freeradius examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set freeradius.secret=YOUR_RADIUS_SECRET \
  --set mysql.rootPassword=YOUR_ROOT_PASSWORD \
  --set mysql.password=YOUR_DB_PASSWORD
```

### With External MySQL

```bash
helm install freeradius examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set mysql.enabled=false \
  --set externalMysql.host=mysql.example.com \
  --set externalMysql.password=YOUR_DB_PASSWORD \
  --set freeradius.secret=YOUR_RADIUS_SECRET
```

### Using values file

```bash
# Copy and edit values
cp values.yaml my-values.yaml
# Edit my-values.yaml

helm install freeradius examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  -f my-values.yaml
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `freeradius.replicaCount` | Number of FreeRADIUS pods | `2` |
| `freeradius.image.repository` | Image repository | `freeradius` |
| `freeradius.image.tag` | Image tag | `latest` |
| `freeradius.secret` | RADIUS shared secret | `CHANGE_ME_RADIUS_SECRET` |
| `freeradius.clients` | Additional clients (CIDR) | `""` |
| `freeradius.service.type` | Service type | `LoadBalancer` |
| `mysql.enabled` | Deploy MySQL | `true` |
| `mysql.rootPassword` | MySQL root password | `CHANGE_ME_ROOT_PASSWORD` |
| `mysql.password` | MySQL user password | `CHANGE_ME_STRONG_PASSWORD` |
| `mysql.persistence.size` | PVC size | `10Gi` |

### External MySQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalMysql.host` | External MySQL host | `""` |
| `externalMysql.port` | External MySQL port | `3306` |
| `externalMysql.database` | Database name | `radius` |
| `externalMysql.user` | Database user | `radius` |
| `externalMysql.password` | Database password | `""` |

## Examples

### Production with HA MySQL

```yaml
# production-values.yaml
freeradius:
  replicaCount: 3
  secret: "super-secure-secret"
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "1000m"

mysql:
  enabled: false

externalMysql:
  host: "mysql-cluster.database.svc"
  port: 3306
  database: "radius"
  user: "radius"
  password: "db-password"
```

### With Custom Clients

```yaml
freeradius:
  secret: "my-secret"
  clients: "10.42.0.0/16,192.168.0.0/16"
```

### NodePort Service

```yaml
freeradius:
  service:
    type: NodePort
```

## Upgrade

```bash
helm upgrade freeradius examples/helm/freeradius \
  --namespace freeradius \
  -f my-values.yaml
```

## Uninstall

```bash
helm uninstall freeradius --namespace freeradius
kubectl delete namespace freeradius  # Optional: remove namespace
```

## Troubleshooting

```bash
# Check pods
kubectl -n freeradius get pods

# Check logs
kubectl -n freeradius logs -l app.kubernetes.io/name=freeradius

# Debug FreeRADIUS
kubectl -n freeradius exec -it deploy/freeradius -- freeradius -X
```
