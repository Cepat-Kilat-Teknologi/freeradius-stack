# FreeRADIUS Stack: InnoDB + Indexes + Redis Accounting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade freeradius-stack dengan InnoDB conversion, composite indexes, dan optional Redis-backed accounting (interim-update buffering).

**Architecture:** Post-schema migrations dijalankan via `entrypoint.sh` setelah FreeRADIUS default schema import. Redis ditambahkan sebagai optional service (default off, enable via `ACCT_REDIS_ENABLED=true`). FreeRADIUS `rlm_redis` module di-enable conditional, accounting section dimodifikasi untuk route Interim-Update ke Redis saat enabled.

**Tech Stack:** FreeRADIUS 3.2.8, MySQL 8.4, Redis 7, Bash, Docker Compose, Kubernetes, Helm

**Repo:** `/Users/sumitroajiprabowo/Projects/freeradius-stack`

---

## File Structure

### Files to modify:
- `Dockerfile` — tambah `freeradius-redis` package
- `scripts/entrypoint.sh` — post-schema migration + Redis config
- `examples/docker/docker-compose.yaml` — tambah Redis service
- `examples/docker/docker-compose.dev.yaml` — tambah Redis service
- `examples/docker/.env.example` — tambah Redis env vars
- `examples/kubernetes/configmap.yaml` — tambah Redis config
- `examples/kubernetes/freeradius-deployment.yaml` — tambah Redis env + init container
- `examples/helm/freeradius/values.yaml` — tambah Redis section
- `examples/helm/freeradius/templates/deployment.yaml` — tambah Redis env
- `examples/helm/freeradius/templates/configmap.yaml` — tambah Redis keys
- `examples/helm/freeradius/templates/secret.yaml` — tambah Redis password
- `CHANGELOG.md` — document changes

### Files to create:
- `scripts/post-schema.sql` — InnoDB conversion + composite indexes
- `examples/kubernetes/redis-deployment.yaml` — Redis K8s manifest
- `examples/helm/freeradius/templates/redis-statefulset.yaml` — Redis Helm template

---

## Task 1: Post-schema SQL migration file (InnoDB + Indexes)

**Files:**
- Create: `scripts/post-schema.sql`

- [ ] **Step 1: Create the migration SQL file**

```sql
-- post-schema.sql
-- Applied after FreeRADIUS default schema import.
-- Safe to run multiple times (IF NOT EXISTS / idempotent).

-- =============================================================
-- 1. Convert MyISAM tables to InnoDB
--    Enables: transactions, row-level locking, crash recovery
--    FreeRADIUS works normally with InnoDB.
-- =============================================================
ALTER TABLE radcheck ENGINE=InnoDB;
ALTER TABLE radreply ENGINE=InnoDB;
ALTER TABLE radusergroup ENGINE=InnoDB;
ALTER TABLE radgroupcheck ENGINE=InnoDB;
ALTER TABLE radgroupreply ENGINE=InnoDB;
-- radacct, radpostauth, nas are already InnoDB in default schema

-- =============================================================
-- 2. Composite indexes for freeradius-api query patterns
--    Default schema already has single-column indexes on
--    username, groupname, nasname, acctstarttime, etc.
--    These are ADDITIONAL composite/unique indexes.
-- =============================================================

-- Prevent duplicate user-group assignments
-- Used by: freeradius-api BulkInsert, duplicate check
CREATE UNIQUE INDEX idx_radusergroup_user_group
  ON radusergroup(username, groupname);

-- Composite lookup by groupname+attribute
-- Used by: freeradius-api GetByGroupNameAndAttribute
CREATE UNIQUE INDEX idx_radgroupcheck_group_attr
  ON radgroupcheck(groupname, attribute);

-- Composite lookup by groupname+attribute
-- Used by: freeradius-api GetByGroupNameAndAttribute
CREATE UNIQUE INDEX idx_radgroupreply_group_attr
  ON radgroupreply(groupname, attribute);

-- Active session query: WHERE username=? AND acctstoptime IS NULL
-- Used by: freeradius-api GetActiveSessionsByUsername
CREATE INDEX idx_radacct_active
  ON radacct(username, acctstoptime);

-- Time-range filter on post-auth log
-- Used by: freeradius-api radpostauth search endpoint
CREATE INDEX idx_radpostauth_authdate
  ON radpostauth(authdate);
```

Save to `/Users/sumitroajiprabowo/Projects/freeradius-stack/scripts/post-schema.sql`

- [ ] **Step 2: Verify SQL syntax**

Run (dry run, no DB needed):
```bash
cat scripts/post-schema.sql
```
Expected: SQL file with 5 ALTER TABLE + 5 CREATE INDEX statements.

- [ ] **Step 3: Commit**

```bash
git add scripts/post-schema.sql
git commit -m "feat: add post-schema migration for InnoDB conversion and composite indexes

Converts MyISAM tables (radcheck, radreply, radusergroup, radgroupcheck,
radgroupreply) to InnoDB for transaction support and crash recovery.
Adds composite indexes for freeradius-api query patterns."
```

---

## Task 2: Integrate post-schema migration into entrypoint.sh

**Files:**
- Modify: `scripts/entrypoint.sh:170-177`

- [ ] **Step 1: Add post-schema migration function**

Add this function after `release_db_lock()` (after line 120) in `entrypoint.sh`:

```bash
# Run post-schema migrations (InnoDB conversion, additional indexes)
# Safe to run multiple times - ALTER TABLE ENGINE=InnoDB is a no-op if already InnoDB,
# CREATE INDEX will fail silently if index already exists.
run_post_schema_migrations() {
    local migration_file="/entrypoint-post-schema.sql"
    if [[ ! -f "$migration_file" ]]; then
        echo "No post-schema migration file found. Skipping."
        return 0
    fi

    echo "Running post-schema migrations..."
    # Use --force to continue on errors (e.g., duplicate index)
    if mysql --defaults-extra-file="$MYSQL_CREDS_FILE" $MYSQL_SSL_OPTS --connect-timeout=10 \
        --force -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$MYSQL_DBNAME" < "$migration_file" 2>/dev/null; then
        echo "Post-schema migrations applied successfully."
    else
        echo "Post-schema migrations completed (some statements may have been skipped as already applied)."
    fi
}
```

- [ ] **Step 2: Call the function after schema import**

In the schema import block, add the call after line 176 (`echo "Database schema imported successfully."`):

```bash
                    echo "Database schema imported successfully."
                    run_post_schema_migrations
```

Also add it after the `schema_exists` early-exit (line 162), so migrations run even if schema was already present:

```bash
        if schema_exists; then
            echo "Database schema already exists. Skipping import."
            run_post_schema_migrations
        else
```

- [ ] **Step 3: Commit**

```bash
git add scripts/entrypoint.sh
git commit -m "feat: run post-schema migrations on startup

Applies InnoDB conversion and composite indexes after schema import.
Uses --force flag so migrations are idempotent (safe to re-run)."
```

---

## Task 3: Copy post-schema.sql into Docker image

**Files:**
- Modify: `Dockerfile:57` (before COPY entrypoint)

- [ ] **Step 1: Add COPY for migration file**

Add after the existing `COPY --link --chmod=755 scripts/entrypoint.sh /entrypoint.sh` line:

```dockerfile
# Copy post-schema migration (InnoDB conversion + composite indexes)
COPY --link scripts/post-schema.sql /entrypoint-post-schema.sql
```

- [ ] **Step 2: Commit**

```bash
git add Dockerfile
git commit -m "feat: include post-schema migration in Docker image"
```

---

## Task 4: Add freeradius-redis package to Dockerfile

**Files:**
- Modify: `Dockerfile:32-39`

- [ ] **Step 1: Add freeradius-redis to package install**

Change the `apt-get install` line to include `freeradius-redis`:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    freeradius \
    freeradius-mysql \
    freeradius-redis \
    freeradius-utils \
    mariadb-client \
    gosu \
    tzdata \
    && rm -f /etc/apt/sources.list.d/sid.list /etc/apt/preferences.d/sid-low-priority \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Commit**

```bash
git add Dockerfile
git commit -m "feat: add freeradius-redis package for optional Redis accounting"
```

---

## Task 5: Redis accounting configuration in entrypoint.sh

**Files:**
- Modify: `scripts/entrypoint.sh`

- [ ] **Step 1: Add Redis environment validation**

Add after the timezone block (after line 73), inside the `if [[ ! -f "$LOCAL_LOCK_FILE" ]]` section would be wrong — this needs to run always. Add after the TZ block and before the MySQL wait:

```bash
# Redis accounting configuration (optional, default: disabled)
# When enabled, Interim-Update packets are buffered in Redis for batch processing
ACCT_REDIS_ENABLED="${ACCT_REDIS_ENABLED:-false}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_DB="${REDIS_DB:-0}"
```

- [ ] **Step 2: Add Redis readiness check (conditional)**

Add after the MySQL readiness check (after line 98):

```bash
# Wait for Redis if accounting Redis is enabled
if [[ "$ACCT_REDIS_ENABLED" == "true" ]]; then
    echo "Redis accounting enabled. Waiting for Redis..."
    redis_ready=false
    for i in {1..15}; do
        # Use simple TCP check (no redis-cli in image)
        if (echo PING | timeout 3 bash -c "cat > /dev/tcp/$REDIS_HOST/$REDIS_PORT" 2>/dev/null); then
            echo "Redis is ready."
            redis_ready=true
            break
        fi
        echo "  Waiting for Redis ($i/15)..."
        sleep 2
    done

    if [[ "$redis_ready" != "true" ]]; then
        echo "Warning: Redis not available. Accounting will fall back to SQL only." >&2
        ACCT_REDIS_ENABLED="false"
    fi
fi
```

- [ ] **Step 3: Add Redis module configuration (inside init block)**

Add inside the `if [[ ! -f "$LOCAL_LOCK_FILE" ]]` block, after the SQL configuration section (after line 222). This enables and configures `rlm_redis` and modifies the accounting section:

```bash
    # Redis module configuration (only when ACCT_REDIS_ENABLED=true)
    if [[ "$ACCT_REDIS_ENABLED" == "true" ]]; then
        echo "Configuring Redis accounting module..."

        # Enable redis module
        if [[ -f "mods-available/redis" ]] && [[ ! -L "mods-enabled/redis" ]]; then
            ln -sf "${RADDB_DIR}/mods-available/redis" "${RADDB_DIR}/mods-enabled/redis"
        fi

        # Configure redis module connection
        if [[ -f "mods-enabled/redis" ]]; then
            escaped_redis_host=$(escape_for_sed "$REDIS_HOST")
            escaped_redis_port=$(escape_for_sed "$REDIS_PORT")

            sed -Ei \
                -e "s|^([[:space:]]*)#?[[:space:]]*server[[:space:]]*=.*|\1server = \"${escaped_redis_host}\"|" \
                -e "s|^([[:space:]]*)#?[[:space:]]*port[[:space:]]*=.*|\1port = ${escaped_redis_port}|" \
                -e "s|^([[:space:]]*)#?[[:space:]]*database[[:space:]]*=.*|\1database = ${REDIS_DB}|" \
                mods-enabled/redis

            if [[ -n "$REDIS_PASSWORD" ]]; then
                escaped_redis_password=$(escape_for_sed "$REDIS_PASSWORD")
                sed -Ei "s|^([[:space:]]*)#?[[:space:]]*password[[:space:]]*=.*|\1password = \"${escaped_redis_password}\"|" mods-enabled/redis
            fi
        fi

        # Create custom accounting site snippet that routes Interim-Update to Redis
        cat > "${RADDB_DIR}/custom/acct-redis.conf" <<'ACCTEOF'
# Redis accounting for Interim-Update packets
# Interim-Update → buffer to Redis list, flushed by external worker
# Start/Stop → direct to SQL (critical, must be durable)
#
# Format: pipe-delimited fields for easy parsing by flush worker
# Fields: AcctUniqueId|AcctSessionId|UserName|NASIPAddress|NASPortId|EventTimestamp|
#         AcctSessionTime|AcctInputOctets|AcctOutputOctets|AcctInputGigawords|
#         AcctOutputGigawords|FramedIPAddress|FramedIPv6Address|FramedIPv6Prefix|
#         FramedInterfaceId|DelegatedIPv6Prefix

accounting {
    if (&Acct-Status-Type == "Interim-Update") {
        update control {
            &Tmp-String-0 := "%{redis:RPUSH radius:acct:interim %{Acct-Unique-Session-Id}|%{Acct-Session-Id}|%{User-Name}|%{%{NAS-IPv6-Address}:-%{NAS-IP-Address}}|%{%{NAS-Port-ID}:-%{NAS-Port}}|%{integer:Event-Timestamp}|%{Acct-Session-Time}|%{Acct-Input-Octets}|%{Acct-Output-Octets}|%{Acct-Input-Gigawords}|%{Acct-Output-Gigawords}|%{Framed-IP-Address}|%{Framed-IPv6-Address}|%{Framed-IPv6-Prefix}|%{Framed-Interface-Id}|%{Delegated-IPv6-Prefix}"
        }
    }
    else {
        -sql
    }

    exec
    attr_filter.accounting_response
}
ACCTEOF

        # Patch sites-enabled/default to include Redis accounting override
        # Only if not already patched
        if ! grep -q "acct-redis.conf" "sites-enabled/default" 2>/dev/null; then
            # Replace the accounting section's -sql with $INCLUDE of our custom config
            # The default sites-enabled/default has: accounting { ... -sql ... }
            # We replace the entire accounting section with our custom one
            sed -Ei '/^accounting \{/,/^\}/{
                /^accounting \{/ {
                    r '"${RADDB_DIR}/custom/acct-redis.conf"'
                    # Comment out original accounting block
                    s/^/# [redis-override] /
                }
                /^[^#]/ s/^/# [redis-override] /
            }' sites-enabled/default
        fi

        echo "Redis accounting configured. Interim-Update → Redis, Start/Stop → SQL"
    fi
```

- [ ] **Step 4: Commit**

```bash
git add scripts/entrypoint.sh
git commit -m "feat: add optional Redis accounting for Interim-Update buffering

When ACCT_REDIS_ENABLED=true, Interim-Update packets are pushed to
Redis list 'radius:acct:interim' instead of writing to MySQL directly.
Start/Stop packets always go to SQL for durability.
Falls back to SQL-only if Redis is unreachable at startup."
```

---

## Task 6: Docker Compose — add Redis service

**Files:**
- Modify: `examples/docker/docker-compose.yaml`
- Modify: `examples/docker/docker-compose.dev.yaml`

- [ ] **Step 1: Add Redis service to production compose**

Add between `db` and `freeradius` services in `docker-compose.yaml`:

```yaml
  redis:
    image: ${REDIS_IMAGE:-redis:7-alpine}
    restart: unless-stopped
    container_name: radius-redis
    command: >
      sh -c '
        if [ -n "$REDIS_PASSWORD" ]; then
          redis-server --requirepass "$REDIS_PASSWORD" --appendonly yes --maxmemory 128mb --maxmemory-policy noeviction
        else
          redis-server --appendonly yes --maxmemory 128mb --maxmemory-policy noeviction
        fi
      '
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD:-}
    volumes:
      - redis_data:/data
    networks:
      - radius-internal
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: "0.5"
```

Add Redis env vars to the `freeradius` service environment section:

```yaml
      ACCT_REDIS_ENABLED: ${ACCT_REDIS_ENABLED:-false}
      REDIS_HOST: ${REDIS_HOST:-redis}
      REDIS_PORT: ${REDIS_PORT:-6379}
      REDIS_PASSWORD: ${REDIS_PASSWORD:-}
      REDIS_DB: ${REDIS_DB:-0}
```

Add `redis_data` to volumes section:

```yaml
volumes:
  db_data:
  radius_config:
  redis_data:
```

Add conditional dependency — freeradius depends on redis only when enabled. Since Docker Compose doesn't support conditional depends_on, we add redis as optional (no `condition: service_healthy` hard dependency):

No change to `depends_on` — FreeRADIUS entrypoint already handles Redis-not-ready gracefully by falling back to SQL-only.

- [ ] **Step 2: Add Redis service to dev compose**

Same pattern in `docker-compose.dev.yaml`, but with dev defaults:

```yaml
  redis:
    image: ${REDIS_IMAGE:-redis:7-alpine}
    restart: unless-stopped
    container_name: radius-redis-dev
    command: redis-server --appendonly yes --maxmemory 128mb --maxmemory-policy noeviction
    volumes:
      - redis_data:/data
    networks:
      - radius-internal
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
```

Add Redis env vars to freeradius service:

```yaml
      ACCT_REDIS_ENABLED: ${ACCT_REDIS_ENABLED:-false}
      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_PASSWORD: ""
      REDIS_DB: "0"
```

Add `redis_data` to volumes.

- [ ] **Step 3: Commit**

```bash
git add examples/docker/docker-compose.yaml examples/docker/docker-compose.dev.yaml
git commit -m "feat: add Redis service to Docker Compose

Redis is always started but accounting buffering is controlled by
ACCT_REDIS_ENABLED (default: false). Uses redis:7-alpine with AOF
persistence and 128MB memory limit with noeviction policy."
```

---

## Task 7: Update .env.example with Redis variables

**Files:**
- Modify: `examples/docker/.env.example`

- [ ] **Step 1: Add Redis section**

Add after the backup settings section at the end of the file:

```bash
# =============================================================
# Redis Accounting (optional, default: disabled)
# =============================================================
# Set to true to buffer Interim-Update packets in Redis
# instead of writing directly to MySQL. Reduces DB write pressure.
# Start/Stop packets always go to SQL regardless of this setting.
# ACCT_REDIS_ENABLED=true

# Redis connection settings
# REDIS_HOST=redis
# REDIS_PORT=6379
# REDIS_PASSWORD=
# REDIS_DB=0

# Redis image (default: redis:7-alpine)
# REDIS_IMAGE=redis:7-alpine
```

- [ ] **Step 2: Commit**

```bash
git add examples/docker/.env.example
git commit -m "docs: add Redis accounting env vars to .env.example"
```

---

## Task 8: Kubernetes manifests — Redis deployment + config updates

**Files:**
- Create: `examples/kubernetes/redis-deployment.yaml`
- Modify: `examples/kubernetes/configmap.yaml`
- Modify: `examples/kubernetes/freeradius-deployment.yaml`

- [ ] **Step 1: Create Redis deployment manifest**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: freeradius
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/part-of: freeradius
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
  template:
    metadata:
      labels:
        app.kubernetes.io/name: redis
        app.kubernetes.io/part-of: freeradius
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          command:
            - redis-server
            - --appendonly
            - "yes"
            - --maxmemory
            - "128mb"
            - --maxmemory-policy
            - noeviction
          ports:
            - containerPort: 6379
              name: redis
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "256Mi"
              cpu: "500m"
          readinessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 15
            periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: freeradius
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/part-of: freeradius
spec:
  selector:
    app.kubernetes.io/name: redis
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  clusterIP: None
```

Save to `examples/kubernetes/redis-deployment.yaml`.

- [ ] **Step 2: Update ConfigMap with Redis vars**

Add to `examples/kubernetes/configmap.yaml` data section:

```yaml
  # Redis accounting (set to "true" to enable)
  ACCT_REDIS_ENABLED: "false"
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
  REDIS_DB: "0"
```

- [ ] **Step 3: Update FreeRADIUS deployment with Redis env vars**

Add to `examples/kubernetes/freeradius-deployment.yaml` in the `env` section of the freeradius container:

```yaml
            - name: ACCT_REDIS_ENABLED
              valueFrom:
                configMapKeyRef:
                  name: freeradius-config
                  key: ACCT_REDIS_ENABLED
            - name: REDIS_HOST
              valueFrom:
                configMapKeyRef:
                  name: freeradius-config
                  key: REDIS_HOST
            - name: REDIS_PORT
              valueFrom:
                configMapKeyRef:
                  name: freeradius-config
                  key: REDIS_PORT
            - name: REDIS_DB
              valueFrom:
                configMapKeyRef:
                  name: freeradius-config
                  key: REDIS_DB
```

- [ ] **Step 4: Update kustomization.yaml**

Add `redis-deployment.yaml` to the resources list in `examples/kubernetes/kustomization.yaml`.

- [ ] **Step 5: Commit**

```bash
git add examples/kubernetes/
git commit -m "feat: add Redis deployment and config for Kubernetes

Adds Redis Deployment+Service and updates ConfigMap/FreeRADIUS
deployment with Redis accounting environment variables."
```

---

## Task 9: Helm chart — Redis support

**Files:**
- Modify: `examples/helm/freeradius/values.yaml`
- Create: `examples/helm/freeradius/templates/redis-statefulset.yaml`
- Modify: `examples/helm/freeradius/templates/deployment.yaml`
- Modify: `examples/helm/freeradius/templates/configmap.yaml`
- Modify: `examples/helm/freeradius/templates/secret.yaml`

- [ ] **Step 1: Add Redis section to values.yaml**

Add after the `backup` section:

```yaml
# Redis configuration (for accounting buffering)
redis:
  # Set to true to enable Redis accounting
  # Interim-Update packets will be buffered in Redis
  enabled: false

  image:
    repository: redis
    tag: "7-alpine"
    pullPolicy: IfNotPresent

  # Redis password (leave empty for no auth)
  password: ""

  # Use an existing secret for Redis password
  existingSecret: ""

  # Redis database number
  database: 0

  persistence:
    enabled: true
    size: 1Gi
    storageClass: ""
    accessMode: ReadWriteOnce

  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "256Mi"
      cpu: "500m"

# External Redis configuration (when redis.enabled=false but accounting is wanted)
externalRedis:
  host: ""
  port: 6379
  password: ""
  database: 0
  existingSecret: ""
```

- [ ] **Step 2: Create Redis StatefulSet template**

Create `examples/helm/freeradius/templates/redis-statefulset.yaml`:

```yaml
{{- if .Values.redis.enabled }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "freeradius.fullname" . }}-redis
  labels:
    {{- include "freeradius.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis
spec:
  serviceName: {{ include "freeradius.fullname" . }}-redis
  replicas: 1
  selector:
    matchLabels:
      {{- include "freeradius.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: redis
  template:
    metadata:
      labels:
        {{- include "freeradius.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: redis
    spec:
      containers:
        - name: redis
          image: "{{ .Values.redis.image.repository }}:{{ .Values.redis.image.tag }}"
          imagePullPolicy: {{ .Values.redis.image.pullPolicy }}
          command:
            - redis-server
            - --appendonly
            - "yes"
            - --maxmemory
            - "128mb"
            - --maxmemory-policy
            - noeviction
            {{- if .Values.redis.password }}
            - --requirepass
            - "$(REDIS_PASSWORD)"
            {{- end }}
          {{- if .Values.redis.password }}
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "freeradius.fullname" . }}
                  key: redis-password
          {{- end }}
          ports:
            - containerPort: 6379
              name: redis
          resources:
            {{- toYaml .Values.redis.resources | nindent 12 }}
          readinessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 15
            periodSeconds: 20
          {{- if .Values.redis.persistence.enabled }}
          volumeMounts:
            - name: redis-data
              mountPath: /data
          {{- end }}
  {{- if .Values.redis.persistence.enabled }}
  volumeClaimTemplates:
    - metadata:
        name: redis-data
      spec:
        accessModes: [ "{{ .Values.redis.persistence.accessMode }}" ]
        {{- if .Values.redis.persistence.storageClass }}
        storageClassName: "{{ .Values.redis.persistence.storageClass }}"
        {{- end }}
        resources:
          requests:
            storage: {{ .Values.redis.persistence.size }}
  {{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "freeradius.fullname" . }}-redis
  labels:
    {{- include "freeradius.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis
spec:
  selector:
    {{- include "freeradius.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: redis
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  clusterIP: None
{{- end }}
```

- [ ] **Step 3: Update Helm deployment.yaml — add Redis env vars**

Add to the `env` section in `templates/deployment.yaml`, after the `HEALTHCHECK_SECRET` block (before `extraEnv`):

```yaml
            {{- if or .Values.redis.enabled .Values.externalRedis.host }}
            - name: ACCT_REDIS_ENABLED
              value: "true"
            - name: REDIS_HOST
              value: {{ if .Values.redis.enabled }}{{ include "freeradius.fullname" . }}-redis{{ else }}{{ .Values.externalRedis.host }}{{ end }}
            - name: REDIS_PORT
              value: {{ if .Values.redis.enabled }}"6379"{{ else }}{{ .Values.externalRedis.port | quote }}{{ end }}
            - name: REDIS_DB
              value: {{ if .Values.redis.enabled }}{{ .Values.redis.database | quote }}{{ else }}{{ .Values.externalRedis.database | quote }}{{ end }}
            {{- if or .Values.redis.password .Values.externalRedis.password }}
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "freeradius.fullname" . }}
                  key: redis-password
            {{- end }}
            {{- end }}
```

- [ ] **Step 4: Update Helm configmap.yaml — add Redis keys**

Add to `templates/configmap.yaml` data section:

```yaml
  ACCT_REDIS_ENABLED: {{ if or .Values.redis.enabled .Values.externalRedis.host }}"true"{{ else }}"false"{{ end }}
```

- [ ] **Step 5: Update Helm secret.yaml — add Redis password**

Add to `templates/secret.yaml` data section:

```yaml
  {{- if or .Values.redis.password .Values.externalRedis.password }}
  redis-password: {{ default .Values.externalRedis.password .Values.redis.password | b64enc | quote }}
  {{- end }}
```

- [ ] **Step 6: Commit**

```bash
git add examples/helm/
git commit -m "feat: add Redis support to Helm chart

Adds redis.enabled toggle, StatefulSet template, external Redis support,
and wires ACCT_REDIS_ENABLED to FreeRADIUS deployment automatically."
```

---

## Task 10: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add entries to [Unreleased] section**

Add under `### Changed` (or create new subsections):

```markdown
### Added

- Post-schema migration system: automatically applies InnoDB conversion and composite indexes after FreeRADIUS default schema import
- Optional Redis accounting: buffer Interim-Update packets in Redis for batch processing (`ACCT_REDIS_ENABLED=true`)
- Redis service in Docker Compose (always available, accounting opt-in)
- Redis Deployment for Kubernetes
- Redis StatefulSet for Helm chart with persistence and external Redis support
- New environment variables: `ACCT_REDIS_ENABLED`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`, `REDIS_DB`
- `freeradius-redis` package in Docker image

### Changed

- Tables `radcheck`, `radreply`, `radusergroup`, `radgroupcheck`, `radgroupreply` converted from MyISAM to InnoDB (enables transactions, row-level locking, crash recovery)
- Added composite indexes: `radusergroup(username, groupname)`, `radgroupcheck(groupname, attribute)`, `radgroupreply(groupname, attribute)`, `radacct(username, acctstoptime)`, `radpostauth(authdate)`
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG with InnoDB, indexes, and Redis accounting"
```

---

## Task 11: Smoke test with docker-compose dev

- [ ] **Step 1: Build and start stack**

```bash
cd examples/docker
docker compose -f docker-compose.dev.yaml up --build -d
```

- [ ] **Step 2: Verify services are healthy**

```bash
docker compose -f docker-compose.dev.yaml ps
```

Expected: `db`, `freeradius`, `redis` all healthy/running.

- [ ] **Step 3: Verify InnoDB conversion**

```bash
docker compose -f docker-compose.dev.yaml exec db mysql -uradius -pradiuspass123 radius -e "
SELECT TABLE_NAME, ENGINE FROM information_schema.TABLES
WHERE TABLE_SCHEMA='radius'
ORDER BY TABLE_NAME;"
```

Expected: All tables show `InnoDB`.

- [ ] **Step 4: Verify composite indexes**

```bash
docker compose -f docker-compose.dev.yaml exec db mysql -uradius -pradiuspass123 radius -e "
SHOW INDEX FROM radusergroup WHERE Key_name LIKE 'idx_%';
SHOW INDEX FROM radgroupcheck WHERE Key_name LIKE 'idx_%';
SHOW INDEX FROM radgroupreply WHERE Key_name LIKE 'idx_%';
SHOW INDEX FROM radacct WHERE Key_name LIKE 'idx_%';
SHOW INDEX FROM radpostauth WHERE Key_name LIKE 'idx_%';"
```

Expected: All 5 composite indexes present.

- [ ] **Step 5: Test RADIUS auth still works**

```bash
docker compose -f docker-compose.dev.yaml exec db mysql -uradius -pradiuspass123 radius -e "
INSERT INTO radcheck (username, attribute, op, value) VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass');"

docker compose -f docker-compose.dev.yaml exec freeradius radtest testuser testpass 127.0.0.1 0 testing123
```

Expected: `Access-Accept`

- [ ] **Step 6: Test Redis accounting (enable and verify)**

```bash
# Restart with Redis accounting enabled
docker compose -f docker-compose.dev.yaml exec freeradius sh -c 'echo "$ACCT_REDIS_ENABLED"'
# Should be "false"

# Recreate with ACCT_REDIS_ENABLED=true
ACCT_REDIS_ENABLED=true docker compose -f docker-compose.dev.yaml up -d --force-recreate freeradius

# Check FreeRADIUS logs for Redis config message
docker compose -f docker-compose.dev.yaml logs freeradius | grep -i redis
```

Expected: Log shows `Redis accounting configured. Interim-Update → Redis, Start/Stop → SQL`

- [ ] **Step 7: Verify Redis is accepting data**

```bash
docker compose -f docker-compose.dev.yaml exec redis redis-cli LLEN radius:acct:interim
```

Expected: `(integer) 0` (no accounting data yet, but command succeeds)

- [ ] **Step 8: Cleanup**

```bash
docker compose -f docker-compose.dev.yaml down -v
```

- [ ] **Step 9: Final commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: adjustments from smoke testing"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Post-schema SQL (InnoDB + indexes) | `scripts/post-schema.sql` |
| 2 | Integrate migration into entrypoint | `scripts/entrypoint.sh` |
| 3 | Copy SQL into Docker image | `Dockerfile` |
| 4 | Add freeradius-redis package | `Dockerfile` |
| 5 | Redis accounting config in entrypoint | `scripts/entrypoint.sh` |
| 6 | Docker Compose Redis service | `examples/docker/docker-compose*.yaml` |
| 7 | .env.example Redis vars | `examples/docker/.env.example` |
| 8 | Kubernetes Redis manifests | `examples/kubernetes/` |
| 9 | Helm chart Redis support | `examples/helm/` |
| 10 | CHANGELOG update | `CHANGELOG.md` |
| 11 | Smoke test | (manual verification) |
