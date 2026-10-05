# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-05

### Security

- **SQL escaping hardened (`auto_escape = yes`)**: entrypoint.sh now uncomments
  `auto_escape = yes` in `queries.conf` on every container start. FreeRADIUS
  default (`auto_escape = no`) uses mime-encoding for characters outside
  `safe_characters`, which breaks SQL lookups for usernames containing
  `! # $ % & + ( )` etc. — the mime-encoded value (e.g. `user=21test`) won't
  match the database value (`user!test`). With `auto_escape = yes`, the MySQL
  driver's `mysql_real_escape_string()` handles escaping — only SQL-dangerous
  characters (`'`, `"`, `\`, NUL) are escaped, everything else passes through
  unchanged. All 18 SQL queries in `queries.conf` are affected. FreeRADIUS own
  documentation recommends: "Using `auto_escape` is preferred".

- **NAS whitelist SQL injection fix (`%{SQL-User-Name}`)**: the inline
  `%{sql:...}` queries in the NAS whitelist tenant-isolation check were using
  raw `%{User-Name}`, which bypasses the SQL escaping layer entirely. Fixed to
  use `%{SQL-User-Name}` (the escaped version processed through
  `mysql_real_escape_string()`), matching the escaping behavior of all other
  queries in `queries.conf`. Includes a sed fixup that automatically corrects
  already-injected configs from prior container starts.

- **Fail-closed authentication**: the `authorize` section now rejects any request that
  reaches its end without a credential loaded from the database. Previously an unknown
  user, or a degraded/unreachable SQL backend, could fall through to `Access-Accept`.
  When no credential is known (user not provisioned, or SQL unavailable) the server now
  rejects. Verified end to end: real user + correct password accepts, wrong password and
  unknown users reject, and with the database stopped every request is rejected
  (fail-closed) rather than accepted.
- Removed the unused non-MySQL SQL dialect templates (mongo, postgresql, mssql, oracle,
  ndb) from the image; the active backend is MySQL/MariaDB only.
- Enabled authentication-result logging (`auth = yes`, `auth_badpass = yes`) for
  auditability; passwords are never logged (`auth_goodpass` stays off).

### Added

- **NAS whitelist tenant isolation**: entrypoint.sh injects unlang block in `authorize` section that checks the `user_nas_whitelist` table (managed by freeradius-api migration 000004) to restrict users to specific NAS/BNG devices. Users with whitelist entries can only authenticate from whitelisted NAS IPs; users without entries are unrestricted. Graceful degradation, if the table doesn't exist, authentication continues normally.
- **Dot-separator realm check toggle (`RADIUS_REQUIRE_DOT_IN_REALM`)**: entrypoint.sh
  disables the FreeRADIUS default `filter_username` rule that rejects realms without
  a dot separator (e.g. `@bumdes` rejected, `@megadata.net.id` passes). ISP PPPoE
  deployments use single-label realms as tenant identifiers — they are not DNS domains.
  Set `RADIUS_REQUIRE_DOT_IN_REALM=true` to re-enable for eduroam/enterprise setups.
  Ref: BUG-2026-10-05 — 328+ `@bumdes` users rejected for ~3 hours.
- Post-schema migration system: automatically applies InnoDB conversion and composite indexes after FreeRADIUS default schema import
- Optional Redis accounting: buffer Interim-Update packets in Redis for batch processing (`ACCT_REDIS_ENABLED=true`)
- Redis service in Docker Compose (always available, accounting opt-in via env var)
- Redis Deployment and Service for Kubernetes
- Redis StatefulSet for Helm chart with persistence and external Redis support
- New environment variables: `ACCT_REDIS_ENABLED`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`, `REDIS_DB`
- `freeradius-redis` package in Docker image for `rlm_redis` module

### Changed

- Tables `radcheck`, `radreply`, `radusergroup`, `radgroupcheck`, `radgroupreply` converted from MyISAM to InnoDB (enables transactions, row-level locking, crash recovery)
- Added composite indexes: `radusergroup(username, groupname)`, `radgroupcheck(groupname, attribute)`, `radgroupreply(groupname, attribute)`, `radacct(username, acctstoptime)`, `radpostauth(authdate)`

- Upgraded FreeRADIUS to 3.2.8 from Debian sid with apt pinning
- Replaced all `:latest` image tags with semantic versioning (`3.2.8`)
- Removed `:latest` tag from CI pipeline (only semantic versions pushed)
- Removed hardcoded version string from entrypoint log message
- Aligned `RADIUS_ALLOW_PRIVATE_NETWORKS` default to `true` across all compose files
- Increased FreeRADIUS liveness probe `initialDelaySeconds` from 15s to 60s (prevents CrashLoopBackOff on first deploy)

### Fixed

- Fixed `/etc/freeradius` permission issue in hardened containers (`cap_drop: ALL`)
- Fixed CI test job: `.env` heredoc whitespace, wait-for-healthy logic, radtest secret mismatch
- Fixed Docker Compose not forwarding `DO_NOT_IMPORT_DB`, `MYSQL_TLS_CA/CERT/KEY` to container
- Fixed Helm `mysql.existingSecret` and `externalMysql.existingSecret` being ignored (dead values)
- Fixed Helm `test-connection.yaml` ignoring `existingSecret` configuration
- Fixed Helm `securityContext` merge producing duplicate YAML keys
- Fixed Kubernetes MySQL StatefulSet missing `fsGroup: 999` (PVC permission failures on fresh deploy)
- Fixed Kubernetes `RADIUS_ALLOW_PRIVATE_NETWORKS` not set (silently defaulting to `true` in entrypoint)
- Fixed entrypoint `escape_for_sed` not escaping pipe character `|` (sed breakage with passwords containing `|`)
- Fixed NetworkPolicy backup pod selector too broad (added `app.kubernetes.io/name` label)
- Fixed Makefile missing `.PHONY` targets and `make logs` dumping full history

### Added

- `docker-compose.dev.yaml` for local development builds from source
- Kubernetes RBAC (Role, RoleBinding, ServiceAccount) for least-privilege enforcement
- Helm RBAC templates (`role.yaml`, `rolebinding.yaml`) with `rbac.create` toggle
- Helm `freeradius.mysql.secretName` helper for proper MySQL secret routing
- Helm backup CronJob now includes `imagePullSecrets` and `serviceAccountName`
- Kubernetes ConfigMap and Deployment now include `RADIUS_ALLOW_PRIVATE_NETWORKS`
- Dev compose logging block with size limits (`max-size: 50m`)
- `.env.example` documents `BACKUP_ENCRYPT_KEY`, `BACKUP_DIR`, `RETENTION_DAYS`
- Helm ServiceMonitor documents exporter sidecar requirement
- Helm NOTES.txt clarifies radtest localhost secret usage
- Governance documentation: SECURITY.md, CONTRIBUTING.md, CHANGELOG.md, CODE_OF_CONDUCT.md
- Upstream FreeRADIUS acknowledgments and source link in README
- Project metadata: .editorconfig, .gitattributes, CODEOWNERS, PR template
- `.playwright-mcp/` added to `.gitignore`

## [1.0.0] - 2026-04-04

### Added

- Security hardening: gosu privilege drop, capability restrictions, no-new-privileges
- NetworkPolicy for MySQL traffic isolation
- PodDisruptionBudget and topologySpreadConstraints for high availability
- RADIUS_SECRET escaping for special characters
- MySQL TLS support via MYSQL_TLS_CA, MYSQL_TLS_CERT, and MYSQL_TLS_KEY environment variables
- Docker Compose hardened configuration (cap_drop, no-new-privileges, init: true)
- CHANGE_ME_* placeholder rejection at startup to prevent deployment with default credentials
- Helm chart: existingSecret support for external secret management
- Helm chart: HorizontalPodAutoscaler (HPA) for automatic scaling
- Helm chart: ServiceMonitor for Prometheus metrics collection
- Helm chart: NetworkPolicy for pod-level traffic control
- Helm chart: imagePullSecrets for private registry support
- CIDR validation for RADIUS_CLIENTS environment variable
- Backup encryption with GPG
- Debug mode via RADIUS_DEBUG environment variable
- MariaDB support as alternative database backend
- Multi-platform Docker images (amd64, arm64)
- CI/CD pipeline with GitHub Actions and Trivy vulnerability scanning
- Distributed database locking for multi-pod schema import

[Unreleased]: https://github.com/Cepat-Kilat-Teknologi/freeradius-stack/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Cepat-Kilat-Teknologi/freeradius-stack/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Cepat-Kilat-Teknologi/freeradius-stack/releases/tag/v1.0.0
