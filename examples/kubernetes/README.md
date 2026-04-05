# Kubernetes Deployment

Deploy FreeRADIUS with MySQL to Kubernetes using plain manifests.

## Prerequisites

- Kubernetes cluster (1.25+)
  - Local: Docker Desktop, Minikube, or Kind
  - Cloud: GKE, EKS, AKS, etc.
- kubectl configured and connected to cluster
- Storage provisioner for PersistentVolumes (default StorageClass)

## Quick Start

### 1. Switch to Local Kubernetes Context (if needed)

```bash
# For Docker Desktop
kubectl config use-context docker-desktop

# For Minikube
kubectl config use-context minikube

# For Kind
kubectl config use-context kind-kind

# Verify cluster is running
kubectl cluster-info
```

### 2. Update Secrets (Important!)

Edit `secret.yaml` and change all default passwords:

```
# WARNING: Do NOT commit this file with real values!
# For production, use:
#   - kubectl create secret generic freeradius-secret --from-literal=...
#   - External Secrets Operator
#   - Sealed Secrets
```

```bash
# Generate secure passwords
openssl rand -base64 32  # Use this for each password

# Edit the secret file
vi secret.yaml
```

Change these values:
- `mysql-root-password`: MySQL root password
- `mysql-password`: MySQL radius user password
- `radius-secret`: RADIUS shared secret for NAS devices
- `healthcheck-secret`: Secret for health check endpoint

### 3. Configure RADIUS Clients (Optional)

Edit `configmap.yaml` to add your NAS devices:

```yaml
RADIUS_CLIENTS: |
  client mynas {
    ipaddr = 192.168.1.0/24
    secret = your-nas-secret
  }
```

### 4. Deploy

```bash
# From this directory
kubectl apply -k .

# Or from project root
make k8s-apply
```

### 5. Wait for Pods to be Ready

```bash
# Watch pods status
kubectl get pods -n freeradius -w

# Expected output (wait until all are Running and Ready):
# NAME                          READY   STATUS    AGE
# freeradius-xxxxx-xxxxx        1/1     Running   2m
# freeradius-xxxxx-xxxxx        1/1     Running   2m
# mysql-0                       1/1     Running   3m
```

### 6. Verify Deployment

```bash
# Check all resources
kubectl get all -n freeradius

# Check services
kubectl get svc -n freeradius
```

## Services

| Service | Type | Ports | Description |
|---------|------|-------|-------------|
| `freeradius` | LoadBalancer | 1812/UDP, 1813/UDP | RADIUS auth & accounting |
| `freeradius-status` | ClusterIP | 18121/UDP | Health check endpoint |
| `mysql` | ClusterIP | 3306/TCP | MySQL database |
| `mysql-headless` | ClusterIP (None) | 3306/TCP | StatefulSet headless service |

```yaml
# Restrict source IPs (recommended for production):
# loadBalancerSourceRanges:
#   - 10.0.0.0/8
```

## Testing

### Add Test User

```bash
# Get MySQL password from secret
MYSQL_PASS=$(kubectl get secret freeradius-secret -n freeradius -o jsonpath='{.data.mysql-password}' | base64 -d)

# Add test user
kubectl exec -n freeradius mysql-0 -- mysql -u radius -p"$MYSQL_PASS" radius -e \
  "INSERT INTO radcheck (username, attribute, op, value) VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass') ON DUPLICATE KEY UPDATE value='testpass';"
```

### Test Authentication

```bash
# Test from inside the cluster (recommended)
kubectl exec -n freeradius deploy/freeradius -- radtest testuser testpass 127.0.0.1 0 testing123

# Expected output:
# Received Access-Accept Id xxx from 127.0.0.1:1812
```

### Test from Local Machine

If you have `radtest` installed locally:

```bash
# Get RADIUS secret
RADIUS_SECRET=$(kubectl get secret freeradius-secret -n freeradius -o jsonpath='{.data.radius-secret}' | base64 -d)

# For LoadBalancer (Docker Desktop exposes on localhost)
radtest testuser testpass localhost 0 "$RADIUS_SECRET"

# For NodePort or port-forward
kubectl -n freeradius port-forward svc/freeradius 1812:1812/udp &
radtest testuser testpass localhost 0 "$RADIUS_SECRET"
```

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace definition |
| `secret.yaml` | Secrets (passwords) - **Edit before deploying!** |
| `configmap.yaml` | Configuration (MySQL host, timezone, clients) |
| `mysql-statefulset.yaml` | MySQL StatefulSet with PVC |
| `freeradius-deployment.yaml` | FreeRADIUS Deployment (2 replicas) |
| `backup-cronjob.yaml` | Scheduled backup CronJob |
| `serviceaccount.yaml` | ServiceAccount for FreeRADIUS pods |
| `rbac.yaml` | Role and RoleBinding (least-privilege, empty rules) |
| `networkpolicy.yaml` | NetworkPolicy for MySQL and RADIUS traffic isolation |
| `pdb.yaml` | PodDisruptionBudget for FreeRADIUS |
| `kustomization.yaml` | Kustomize configuration |

## Using External MySQL

To use an external MySQL database instead of the bundled one:

1. Edit `configmap.yaml`:
   ```yaml
   MYSQL_HOST: "your-mysql-host.example.com"
   MYSQL_PORT: "3306"
   ```

2. Edit `secret.yaml` with external DB credentials

3. Deploy without MySQL StatefulSet:
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f secret.yaml
   kubectl apply -f configmap.yaml
   kubectl apply -f freeradius-deployment.yaml
   ```

## Scaling

```bash
# Scale FreeRADIUS replicas
kubectl scale deployment freeradius -n freeradius --replicas=3

# Check status
kubectl get pods -n freeradius
```

## Configuration

### ConfigMap Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MYSQL_HOST` | MySQL hostname | `mysql` |
| `MYSQL_PORT` | MySQL port | `3306` |
| `MYSQL_USER` | MySQL username | `radius` |
| `MYSQL_DBNAME` | Database name | `radius` |
| `TZ` | Timezone | `Asia/Jakarta` |
| `RADIUS_CLIENTS` | Additional RADIUS clients (comma-separated CIDR) | `""` |
| `RADIUS_ALLOW_PRIVATE_NETWORKS` | Allow RFC 1918 ranges as RADIUS clients | `"false"` |

Optional environment variables (not in ConfigMap, set via `kubectl set env`):
- `RADIUS_DEBUG` -- enable FreeRADIUS debug mode (`-X`)
- `DO_NOT_IMPORT_DB` -- skip database schema import on startup

## Security

- **ServiceAccount** with `automountServiceAccountToken: false` (least privilege)
- **RBAC** Role with empty rules (no API server access)
- **SecurityContext** on all containers (capabilities dropped, no privilege escalation)
- **MySQL fsGroup: 999** ensures PVC permissions are correct on fresh provisioning
- **NetworkPolicy** restricts MySQL to FreeRADIUS and backup pods only (both `name` and `component` labels required)
- **Pod Security Standards** labels on namespace (`enforce: baseline`, `warn: restricted`)
- **PodDisruptionBudget** ensures minimum 1 pod during maintenance
- **topologySpreadConstraints** spread pods across nodes
- **CHANGE_ME_* rejection** -- deployment fails if placeholder secrets are used
- FreeRADIUS liveness probe starts at **60s** to avoid CrashLoopBackOff during schema import
- Init container has a **300s timeout** (won't hang forever)
- MySQL has a **startupProbe** (5-minute window for slow first boot)

## Troubleshooting

### Pods stuck in Init state

FreeRADIUS pods wait for MySQL to be ready. Check MySQL status:

```bash
kubectl logs -n freeradius mysql-0
kubectl describe pod mysql-0 -n freeradius
```

### Authentication fails with Access-Reject

1. Verify user exists in database:
   ```bash
   kubectl exec -n freeradius mysql-0 -- mysql -u radius -p radius -e "SELECT * FROM radcheck;"
   ```

2. Check FreeRADIUS logs:
   ```bash
   kubectl logs -n freeradius deploy/freeradius
   ```

### No response from RADIUS server

1. Verify the client is configured in `clients.conf` or `RADIUS_CLIENTS`
2. Check if using correct shared secret
3. Verify network connectivity and firewall rules

### PVC pending

Check if your cluster has a default StorageClass:

```bash
kubectl get storageclass
```

For local clusters without dynamic provisioning, you may need to create a PersistentVolume manually.

### View FreeRADIUS debug logs

```bash
# Check container logs
kubectl logs -n freeradius deploy/freeradius -f

# Exec into container for debugging
kubectl exec -n freeradius deploy/freeradius -it -- bash
```

### Debug Mode

```bash
# Enable debug mode
kubectl set env deployment/freeradius RADIUS_DEBUG=1 -n freeradius
kubectl rollout restart deployment/freeradius -n freeradius
kubectl logs -f deploy/freeradius -n freeradius
```

## Cleanup

```bash
# Delete all resources
kubectl delete -k .

# Delete PVCs (data will be lost!)
kubectl delete pvc -n freeradius --all

# Or from project root
make k8s-delete
```

## Production Considerations

- Change all default passwords in `secret.yaml` (special characters like `/`, `+`, `=` from base64 are supported)
- Use proper TLS certificates for MySQL connections
- Configure appropriate resource limits
- Set up monitoring and alerting
- Use external MySQL for high availability
- NetworkPolicy is included by default for pod isolation
- PDB ensures high availability during cluster maintenance
- Container security: non-root execution, dropped capabilities
- MySQL TLS supported via environment variables
- StartupProbe prevents premature MySQL pod termination
- topologySpreadConstraints for multi-zone spreading