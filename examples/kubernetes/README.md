# Kubernetes Deployment

Deploy FreeRADIUS with MySQL to Kubernetes using plain manifests.

## Prerequisites

- Kubernetes cluster (1.25+)
- kubectl configured
- FreeRADIUS image available (build and push first)

## Quick Start

1. **Pull the image (or build your own):**
   ```bash
   # Pull from Docker Hub
   docker pull cepatkilatteknologi/freeradius:3.2.8

   # Or build and push to your own registry
   make build REGISTRY=your-registry.io/username
   make push REGISTRY=your-registry.io/username
   ```

2. **Update image reference (optional):**
   ```bash
   # The default image is cepatkilatteknologi/freeradius:3.2.8
   # To use GHCR instead, edit freeradius-deployment.yaml:
   # image: ghcr.io/cepat-kilat-teknologi/freeradius:3.2.8
   ```

3. **Update secrets:**
   ```bash
   # Edit secret.yaml - change all CHANGE_ME_* values
   ```

4. **Deploy:**
   ```bash
   kubectl apply -k .
   # Or from root: make k8s-apply
   ```

5. **Verify:**
   ```bash
   kubectl -n freeradius get pods
   kubectl -n freeradius get svc
   ```

## Using External MySQL

To use an external MySQL cluster:

1. Edit `configmap.yaml`:
   ```yaml
   MYSQL_HOST: "your-mysql-host.example.com"
   MYSQL_PORT: "3306"
   ```

2. Edit `secret.yaml` with external DB credentials

3. Remove or skip `mysql-statefulset.yaml`:
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f secret.yaml
   kubectl apply -f configmap.yaml
   kubectl apply -f freeradius-deployment.yaml
   ```

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | Namespace definition |
| `secret.yaml` | Secrets (passwords) |
| `configmap.yaml` | Configuration |
| `mysql-statefulset.yaml` | MySQL StatefulSet + Services |
| `freeradius-deployment.yaml` | FreeRADIUS Deployment + Services |
| `kustomization.yaml` | Kustomize configuration |

## Testing

```bash
# Port forward for testing
kubectl -n freeradius port-forward svc/freeradius 1812:1812/udp

# Add test user (exec into mysql pod)
kubectl -n freeradius exec -it mysql-0 -- mysql -uroot -p radius -e \
  "INSERT INTO radcheck (username, attribute, op, value) VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass');"

# Test auth
radtest testuser testpass localhost 1812 YOUR_SECRET
```

## Cleanup

```bash
kubectl delete -k .
# Or from root: make k8s-delete
```
