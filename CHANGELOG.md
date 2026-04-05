# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Upgraded FreeRADIUS to 3.2.8 from Debian sid with apt pinning
- Replaced all `:latest` image tags with semantic versioning (`3.2.8`)
- Removed `:latest` tag from CI pipeline (only semantic versions pushed)
- Removed hardcoded version string from entrypoint log message

### Fixed

- Fixed `/etc/freeradius` permission issue in hardened containers (`cap_drop: ALL`)

### Added

- `docker-compose.dev.yaml` for local development builds from source
- Kubernetes RBAC (Role, RoleBinding, ServiceAccount) for least-privilege enforcement
- Helm RBAC templates (`role.yaml`, `rolebinding.yaml`) with `rbac.create` toggle
- Governance documentation: SECURITY.md, CONTRIBUTING.md, CHANGELOG.md, CODE_OF_CONDUCT.md
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

[Unreleased]: https://github.com/Cepat-Kilat-Teknologi/freeradius-stack/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Cepat-Kilat-Teknologi/freeradius-stack/releases/tag/v1.0.0
