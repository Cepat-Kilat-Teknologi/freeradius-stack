# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 3.2.8   | :white_check_mark: |
| < 3.2.8 | :x:                |

Only the latest release is actively maintained and receives security patches.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report vulnerabilities by emailing **security@cepatkilatteknologi.com**. Include:

- A description of the vulnerability
- Steps to reproduce the issue
- The affected component (Docker image, entrypoint scripts, Helm chart, Kubernetes manifests)
- Any potential impact assessment

### Response Timeline

| Action                          | Timeframe          |
| ------------------------------- | ------------------ |
| Acknowledgment of report        | Within 48 hours    |
| Initial assessment              | Within 72 hours    |
| Patch for critical issues       | Within 7 days      |
| Patch for non-critical issues   | Within 30 days     |

We will keep you informed of our progress throughout the remediation process.

## Scope

The following components are within the scope of this security policy:

- **Docker image** (Dockerfile, base image configuration)
- **Entrypoint scripts** (`scripts/` directory)
- **Helm chart** (templates, values, chart configuration)
- **Kubernetes manifests** (Deployments, Services, NetworkPolicies, etc.)
- **Docker Compose files** (production and development configurations)
- **CI/CD workflows** (GitHub Actions)
- **NAS whitelist tenant isolation** (unlang injection in entrypoint.sh for multi-tenant NAS access control)

### Out of Scope

The following are **not** covered by this policy. Please report issues to their respective upstream projects:

- **FreeRADIUS core** -- Report to the [FreeRADIUS project](https://freeradius.org/security/)
- **MySQL / MariaDB** -- Report to [Oracle](https://www.oracle.com/security-alerts/) or [MariaDB](https://mariadb.com/kb/en/security/)
- **Base OS packages** in the Debian image -- Report to [Debian Security](https://www.debian.org/security/)

## Security Best Practices

When deploying this stack in production, follow these guidelines:

### Secrets Management

- **Change all default credentials** before deployment. The stack rejects any value containing `CHANGE_ME_` placeholders.
- Use Kubernetes Secrets or an external secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager) for all sensitive values.
- In Helm deployments, use `existingSecret` to reference pre-created Secrets rather than storing credentials in `values.yaml`.

### Network Security

- Enable **NetworkPolicy** to restrict traffic between FreeRADIUS and database pods. The Helm chart and Kubernetes manifests include NetworkPolicy resources by default.
- Place the RADIUS service behind a firewall and restrict access to known NAS/client IP ranges using `RADIUS_CLIENTS` with CIDR notation.
- Never expose the RADIUS management port (18120) externally.

### TLS / Encryption

- Enable **MySQL TLS** using `MYSQL_TLS_CA`, `MYSQL_TLS_CERT`, and `MYSQL_TLS_KEY` environment variables for encrypted database connections.
- Use TLS for RADIUS EAP methods (EAP-TLS, EAP-TTLS, PEAP) with properly signed certificates.
- Enable backup encryption with GPG when using the backup functionality.

### Container Hardening

- The Docker image runs with `cap_drop: ALL` and `no-new-privileges: true` by default.
- FreeRADIUS runs as a non-root user via `gosu` privilege drop.
- Do not override security contexts in Kubernetes unless absolutely necessary.
- Use `readOnlyRootFilesystem: true` where possible.

### Monitoring

- Enable the Prometheus `ServiceMonitor` in Helm to collect RADIUS metrics.
- Monitor container image vulnerabilities with Trivy or equivalent scanning tools.
- Review container logs regularly for authentication anomalies.

### Tenant Isolation (Multi-NAS Whitelist)

- The entrypoint script injects an unlang block in the `authorize` section that checks the `user_nas_whitelist` table on every authentication request.
- Users with whitelist entries can **only** authenticate from whitelisted NAS IP addresses. Requests from non-whitelisted NAS devices are rejected at the RADIUS level — this cannot be bypassed via the API.
- Users **without** whitelist entries are unrestricted (backward compatible).
- The whitelist is managed via [freeradius-api](https://github.com/Cepat-Kilat-Teknologi/freeradius-api) NAS Whitelist endpoints (migration 000004).
- For multi-tenant ISPs: always set NAS whitelist entries during customer provisioning to prevent cross-organization NAS access.

## Disclosure Policy

We follow a coordinated disclosure process. We request that reporters:

1. Allow us reasonable time to address the issue before public disclosure.
2. Make a good-faith effort to avoid accessing or modifying data that does not belong to you.
3. Do not exploit the vulnerability beyond what is necessary to demonstrate the issue.

We credit reporters in our release notes (unless anonymity is requested).
