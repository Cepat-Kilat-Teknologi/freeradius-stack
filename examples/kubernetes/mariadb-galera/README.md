# MariaDB Galera — production HA database for FreeRADIUS

A 3-node synchronous **MariaDB Galera** cluster for the `radius` database, managed by
[mariadb-operator](https://github.com/mariadb-operator/mariadb-operator). Use this for
production instead of the bundled single-pod MySQL (which is a single point of failure).

Galera gives synchronous multi-node replication: the cluster tolerates losing one node
(quorum 2/3) and the operator exposes a single stable **`*-primary`** Service that
FreeRADIUS connects to.

## Files

| File | What |
|------|------|
| `mariadb-radius.yaml` | The 3-node `MariaDB` Galera cluster |
| `mariadb-radius-backup.yaml` | Scheduled logical backups (daily → PVC, 7-day retention) |

> The Kubernetes `Secret` with the DB passwords is **NOT** in this repo. Create it
> out-of-band (below). Never commit real credentials to this public repository.

## Prerequisites

- A Kubernetes cluster with a CSI storage class (examples use `longhorn`).
- If your storage is only available on specific nodes, label them and the cluster
  pins one DB pod per storage node (`nodeSelector: storage=true` in the manifest).

## Deploy

```bash
# 1) Install the operator (CRDs + controller)
helm repo add mariadb-operator https://helm.mariadb.com/mariadb-operator
helm install mariadb-operator-crds mariadb-operator/mariadb-operator-crds -n databases --create-namespace
helm install mariadb-operator      mariadb-operator/mariadb-operator      -n databases

# 2) Create the credentials Secret (generate strong random values — do NOT commit)
kubectl create secret generic mariadb-radius-secret -n databases \
  --from-literal=root-password="$(openssl rand -base64 24)" \
  --from-literal=password="$(openssl rand -base64 24)"

# 3) Deploy the Galera cluster + scheduled backup
kubectl apply -f mariadb-radius.yaml
kubectl apply -f mariadb-radius-backup.yaml

# 4) Wait until ready
kubectl wait --for=condition=Ready mariadb/mariadb-radius -n databases --timeout=300s
```

## Point FreeRADIUS at it

Set the external-DB settings (Helm `values-production.yaml`, or the raw FreeRADIUS
ConfigMap/Secret):

```yaml
mysql:
  enabled: false
externalMysql:
  host: mariadb-radius-primary.databases.svc.cluster.local
  port: 3306
  database: radius
  user: radius
  # password: from the Secret above (existingSecret or --set), never inline
```

The `radius` database, user, and grants are created by the operator. Import an existing
FreeRADIUS schema with `mysqldump | mariadb` if migrating from a previous DB.

## Backups

`mariadb-radius-backup.yaml` creates a CronJob (daily 02:00, 7-day retention) that dumps
to a Longhorn PVC. For off-cluster durability, switch `spec.storage` to S3 and provide
the credentials via a `Secret` reference (not inline). Trigger an immediate run with:

```bash
kubectl create job --from=cronjob/mariadb-radius-backup adhoc-1 -n databases
```

## Sizing notes

- The manifest targets a production workload (e.g. ~10K subscribers): `innodb_buffer_pool_size`,
  connection limits, and storage are sized accordingly — tune to your node capacity.
- For sustained production, give the database **dedicated nodes**. Sharing busy general
  worker nodes leads to CPU-reservation contention.
- For maximum write-path isolation you can front the cluster with the operator's
  `*-primary` / `*-secondary` Services (read/write split) — not required at this scale.
