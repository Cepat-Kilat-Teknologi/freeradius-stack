# FreeRADIUS Helm Chart

Helm chart for deploying FreeRADIUS with MySQL backend on Kubernetes.

## Prerequisites

- Kubernetes 1.25+
  - Local: Docker Desktop, Minikube, or Kind
  - Cloud: GKE, EKS, AKS, etc.
- Helm 3.x
- Storage provisioner for PersistentVolumes (if persistence enabled)

## Startup Time

Expected startup times vary by environment:

| Environment | Database | Replicas | Startup Time |
|-------------|----------|----------|--------------|
| Docker Desktop (8GB RAM) | MySQL 8.4 | 2 | ~5+ minutes |
| Docker Desktop (8GB RAM) | MariaDB 11 | 1 | ~90 seconds |
| Production K8s (16GB+ RAM) | MySQL 8.4 | 2 | ~2-3 minutes |

For faster local development, use `values-local.yaml` (see [Local Development](#local-development)).

## Quick Start

### 1. Switch to Local Kubernetes Context (if needed)

```bash
# For Docker Desktop
kubectl config use-context docker-desktop

# For Minikube
kubectl config use-context minikube

# Verify cluster is running
kubectl cluster-info
```

### 2. Install the Chart

```bash
# Basic installation with default values
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace

# Or with custom secrets (recommended for production)
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set freeradius.secret=YOUR_RADIUS_SECRET \
  --set freeradius.healthcheckSecret=YOUR_HEALTHCHECK_SECRET \
  --set mysql.rootPassword=YOUR_ROOT_PASSWORD \
  --set mysql.password=YOUR_DB_PASSWORD
```

### 3. Wait for Pods to be Ready

```bash
# Watch pods status
kubectl get pods -n freeradius -w

# Expected output (wait until all are Running and Ready):
# NAME                          READY   STATUS    AGE
# freeradius-xxxxx-xxxxx        1/1     Running   2m
# freeradius-xxxxx-xxxxx        1/1     Running   2m
# freeradius-mysql-0            1/1     Running   3m
```

### 4. Verify Installation

```bash
# Check Helm release
helm list -n freeradius

# Check all resources
kubectl get all -n freeradius
```

## Services

| Service | Type | Ports | Description |
|---------|------|-------|-------------|
| `freeradius` | LoadBalancer | 1812/UDP, 1813/UDP | RADIUS auth & accounting |
| `freeradius-status` | ClusterIP | 18121/UDP | Health check endpoint |
| `freeradius-mysql` | ClusterIP | 3306/TCP | MySQL database |
| `freeradius-mysql-headless` | ClusterIP (None) | 3306/TCP | StatefulSet headless service |

## Testing

### Add Test User

```bash
# Get MySQL password from values (default: CHANGE_ME_STRONG_PASSWORD)
kubectl exec -n freeradius freeradius-mysql-0 -- \
  mysql -u radius -p'CHANGE_ME_STRONG_PASSWORD' radius -e \
  "INSERT INTO radcheck (username, attribute, op, value) VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass') ON DUPLICATE KEY UPDATE value='testpass';"
```

### Test Authentication

```bash
# Test from inside the cluster (recommended)
kubectl exec -n freeradius deploy/freeradius -- \
  radtest testuser testpass 127.0.0.1 0 testing123

# Expected output:
# Received Access-Accept Id xxx from 127.0.0.1:1812
```

### Test from Local Machine

If you have `radtest` installed locally:

```bash
# For LoadBalancer (Docker Desktop exposes on localhost)
radtest testuser testpass localhost 0 YOUR_RADIUS_SECRET
```

### Helm Test

```bash
# Run Helm tests to verify deployment
helm test freeradius -n freeradius
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override full release name | `""` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |
| `serviceAccount.create` | Create ServiceAccount | `true` |
| `rbac.create` | Create Role and RoleBinding | `true` |
| `freeradius.replicaCount` | Number of FreeRADIUS pods | `2` |
| `freeradius.image.repository` | Image repository | `cepatkilatteknologi/freeradius` |
| `freeradius.image.tag` | Image tag | `3.2.8` |
| `freeradius.secret` | RADIUS shared secret | `CHANGE_ME_RADIUS_SECRET` |
| `freeradius.healthcheckSecret` | Health check secret | `CHANGE_ME_HEALTHCHECK_SECRET` |
| `freeradius.existingSecret` | Use existing Secret (skip creation) | `""` |
| `freeradius.clients` | Additional clients (CIDR) | `""` |
| `freeradius.service.type` | Service type | `LoadBalancer` |
| `freeradius.service.loadBalancerSourceRanges` | Restrict LB source IPs | `[]` |
| `freeradius.autoscaling.enabled` | Enable HPA | `false` |
| `freeradius.autoscaling.minReplicas` | Min replicas for HPA | `2` |
| `freeradius.autoscaling.maxReplicas` | Max replicas for HPA | `10` |
| `freeradius.autoscaling.targetCPUUtilizationPercentage` | Target CPU % | `70` |
| `freeradius.autoscaling.targetMemoryUtilizationPercentage` | Target memory % | `80` |
| `freeradius.extraEnv` | Additional environment variables | `[]` |
| `freeradius.extraVolumes` | Additional volumes | `[]` |
| `freeradius.extraVolumeMounts` | Additional volume mounts | `[]` |
| `mysql.enabled` | Deploy bundled MySQL | `true` |
| `mysql.image.repository` | MySQL/MariaDB image | `mysql` |
| `mysql.image.tag` | Image tag | `8.4` |
| `mysql.rootPassword` | MySQL root password | `CHANGE_ME_ROOT_PASSWORD` |
| `mysql.password` | MySQL user password | `CHANGE_ME_STRONG_PASSWORD` |
| `mysql.existingSecret` | Use existing Secret for MySQL | `""` |
| `mysql.persistence.enabled` | Enable persistence | `true` |
| `mysql.persistence.size` | PVC size | `10Gi` |
| `mysql.persistence.storageClass` | Storage class | `""` (default) |
| `backup.enabled` | Enable backup CronJob | `true` |
| `backup.schedule` | Backup schedule | `0 2 * * *` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `metrics.serviceMonitor.enabled` | Enable Prometheus ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `"30s"` |
| `metrics.serviceMonitor.labels` | Additional labels | `{}` |

### External MySQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalMysql.host` | External MySQL host | `""` |
| `externalMysql.port` | External MySQL port | `3306` |
| `externalMysql.database` | Database name | `radius` |
| `externalMysql.user` | Database user | `radius` |
| `externalMysql.password` | Database password | `""` |
| `externalMysql.existingSecret` | Use existing Secret for external MySQL | `""` |

## Local Development

For faster startup on resource-constrained machines (laptops with 8GB RAM), use the optimized local development values:

```bash
helm install freeradius ./examples/helm/freeradius \
  -f ./examples/helm/freeradius/values-local.yaml \
  --namespace freeradius \
  --create-namespace
```

**`values-local.yaml` optimizations:**
- Uses MariaDB 11 instead of MySQL 8.4 (faster startup)
- Single replica (reduces resource usage)
- No persistence (uses emptyDir)
- Reduced resource requests
- Backup disabled

This reduces startup time from **5+ minutes to ~90 seconds** on Docker Desktop.

## Installation Options

### With External MySQL

```bash
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set mysql.enabled=false \
  --set externalMysql.host=mysql.example.com \
  --set externalMysql.password=YOUR_DB_PASSWORD \
  --set freeradius.secret=YOUR_RADIUS_SECRET
```

### Without Persistence (for testing)

```bash
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set mysql.persistence.enabled=false \
  --set backup.enabled=false
```

### Using Values File

```bash
# Copy and edit values
cp values.yaml my-values.yaml
# Edit my-values.yaml with your settings

helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  -f my-values.yaml
```

### External Secrets

```bash
# Using an existing Kubernetes Secret
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set freeradius.existingSecret=my-radius-secret \
  --set mysql.existingSecret=my-mysql-secret
```

### Autoscaling

```bash
# Enable HPA
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set freeradius.autoscaling.enabled=true \
  --set freeradius.autoscaling.minReplicas=2 \
  --set freeradius.autoscaling.maxReplicas=10
```

### Monitoring

```bash
# Enable Prometheus ServiceMonitor
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set metrics.serviceMonitor.enabled=true
```

### Network Security

```bash
# Enable NetworkPolicy
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set networkPolicy.enabled=true

# Restrict LoadBalancer source IPs
helm install freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --create-namespace \
  --set freeradius.service.loadBalancerSourceRanges[0]=10.0.0.0/8
```

## Examples

### Production with External HA MySQL

```yaml
# production-values.yaml
freeradius:
  replicaCount: 3
  existingSecret: "production-radius-secret"
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
  service:
    loadBalancerSourceRanges:
      - 10.0.0.0/8

mysql:
  enabled: false

externalMysql:
  host: "mysql-cluster.database.svc"
  existingSecret: "production-mysql-secret"

networkPolicy:
  enabled: true

metrics:
  serviceMonitor:
    enabled: true

backup:
  enabled: false
```

### With Custom RADIUS Clients

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

## Scaling

```bash
# Scale FreeRADIUS replicas
kubectl scale deployment freeradius -n freeradius --replicas=3

# Or via Helm upgrade
helm upgrade freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --set freeradius.replicaCount=3
```

## Upgrade

```bash
helm upgrade freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  -f my-values.yaml
```

## Troubleshooting

### Pods stuck in Pending state

Check if PVC is bound (storage provisioner issue):

```bash
kubectl get pvc -n freeradius
kubectl describe pvc -n freeradius
```

For local testing without proper storage provisioner:

```bash
helm upgrade freeradius ./examples/helm/freeradius \
  --namespace freeradius \
  --set mysql.persistence.enabled=false \
  --set backup.enabled=false
```

### MySQL CrashLoopBackOff

MySQL needs time for initial setup. The chart is configured with appropriate probe timing, but if issues persist:

```bash
# Check MySQL logs
kubectl logs -n freeradius freeradius-mysql-0

# Describe pod for events
kubectl describe pod freeradius-mysql-0 -n freeradius
```

### Authentication fails with Access-Reject

1. Verify user exists in database:
   ```bash
   kubectl exec -n freeradius freeradius-mysql-0 -- \
     mysql -u radius -p'CHANGE_ME_STRONG_PASSWORD' radius -e "SELECT * FROM radcheck;"
   ```

2. Check FreeRADIUS logs:
   ```bash
   kubectl logs -n freeradius deploy/freeradius
   ```

### No response from RADIUS server

1. Verify the client is configured
2. Check if using correct shared secret
3. Verify network connectivity

### Debug FreeRADIUS

```bash
# Check container logs
kubectl logs -n freeradius deploy/freeradius -f

# Exec into container
kubectl exec -n freeradius deploy/freeradius -it -- bash

# Run FreeRADIUS in debug mode (stops normal service)
kubectl exec -n freeradius deploy/freeradius -it -- radiusd -X
```

## Uninstall

```bash
# Uninstall Helm release
helm uninstall freeradius --namespace freeradius

# Delete namespace (removes all resources including PVCs)
kubectl delete namespace freeradius
```

## Production Considerations

- Change all default passwords and secrets (special characters like `/`, `+`, `=` from base64 are supported)
- Containers run as non-root with dropped capabilities
- securityContext enforced on all pods
- CHANGE_ME_* values are rejected during deployment
- existingSecret support for external secret management
- StartupProbe gives MySQL 5 minutes for first boot
- Init container has 300s timeout
- Use external MySQL for high availability
- Configure appropriate resource limits
- Set up monitoring and alerting
- Use proper TLS certificates
- Configure network policies for security
- Enable pod disruption budgets (enabled by default)