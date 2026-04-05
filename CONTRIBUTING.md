# Contributing to FreeRADIUS Stack

Thank you for your interest in contributing to the FreeRADIUS Stack project. This guide covers the process for contributing code, reporting issues, and submitting pull requests.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Commit Messages](#commit-messages)
- [Reporting Issues](#reporting-issues)
- [Keeping Deployment Methods in Sync](#keeping-deployment-methods-in-sync)

## Prerequisites

Ensure you have the following tools installed:

- **Docker** (20.10+) and **Docker Compose** (v2)
- **kubectl** (compatible with your target cluster version)
- **Helm** (3.x)
- **make**
- **Git**

Optional but recommended:

- **shellcheck** for linting shell scripts
- **yamllint** for validating YAML files
- **trivy** for local image vulnerability scanning

## Development Setup

1. **Fork and clone the repository:**

   ```bash
   git clone https://github.com/<your-username>/freeradius-stack.git
   cd freeradius-stack
   ```

2. **Build the local Docker image:**

   ```bash
   make build
   ```

3. **Start the development environment:**

   ```bash
   cd examples/docker
   docker compose -f docker-compose.dev.yaml up -d --build
   ```

   This builds the image from the local Dockerfile and starts FreeRADIUS with MySQL.

4. **Verify the stack is running:**

   ```bash
   docker compose -f docker-compose.dev.yaml ps
   docker compose -f docker-compose.dev.yaml logs freeradius
   ```

5. **Test RADIUS authentication:**

   ```bash
   # Add a test user
   docker compose -f docker-compose.dev.yaml exec -T db \
     mysql -uroot -prootpass123 radius -e \
     "INSERT INTO radcheck (username, attribute, op, value) VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass') ON DUPLICATE KEY UPDATE value='testpass';"

   # Test authentication
   docker compose -f docker-compose.dev.yaml exec -T freeradius \
     radtest testuser testpass localhost 0 testing123
   ```

## Code Style

### Shell Scripts

All shell scripts in the `scripts/` directory must follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html):

- Use `#!/bin/bash` or `#!/bin/sh` as appropriate.
- Indent with 2 spaces (no tabs).
- Use `"${variable}"` for variable expansion (quote and use braces).
- Functions should be declared with the `function_name() { }` syntax.
- Always check return codes; use `set -euo pipefail` at the top of scripts.
- Run `shellcheck` against all modified scripts before submitting.

### YAML Files

- Use 2-space indentation consistently.
- Use descriptive key names.
- Add comments for non-obvious configuration values.
- Validate files with `yamllint` before submitting.

### Dockerfile

- Follow Docker best practices for layer caching and image size.
- Pin base image versions; do not use `:latest`.
- Combine related `RUN` commands to minimize layers.

## Making Changes

1. **Create a feature branch:**

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes.** Keep changes focused on a single concern.

3. **Test all deployment methods** that your change affects (Docker, Kubernetes, Helm).

4. **Commit your changes** following the commit message guidelines below.

5. **Push to your fork:**

   ```bash
   git push origin feature/your-feature-name
   ```

## Testing

### Local Docker Testing

```bash
# Build the image
make build

# Run the full development stack
docker compose -f docker-compose.dev.yaml up -d

# Run tests
make test

# Check logs for errors
docker compose -f docker-compose.dev.yaml logs freeradius
```

### Helm Chart Testing

```bash
# Lint the chart
helm lint examples/helm/freeradius

# Template rendering (dry-run)
helm template test-release examples/helm/freeradius --debug

# Install in a test namespace
helm install test-release examples/helm/freeradius \
  -f examples/helm/freeradius/values-local.yaml \
  --namespace freeradius-test --create-namespace

# Run Helm tests
helm test test-release --namespace freeradius-test
```

### Kubernetes Manifest Testing

```bash
# Validate manifests
kubectl apply --dry-run=client -k examples/kubernetes/

# Deploy to a test namespace
kubectl apply -k examples/kubernetes/
```

### Security Scanning

```bash
# Scan the Docker image with Trivy
trivy image freeradius-local:dev
```

## Pull Request Process

1. **Fork** the repository and create a branch from `main`.
2. **Make your changes** and ensure all tests pass.
3. **Update documentation** if your change affects deployment steps, environment variables, or configuration options.
4. **Submit a pull request** against the `main` branch.
5. **Fill out the PR template** with a clear description of the change, motivation, and testing performed.
6. **Address review feedback** promptly. All conversations must be resolved before merging.

### PR Requirements

- All CI checks must pass (linting, image build, Trivy scan).
- At least one maintainer approval is required.
- The PR description must explain what changed and why.
- Breaking changes must be clearly documented.

## Commit Messages

Follow these conventions for commit messages:

- **Use imperative mood** in the subject line (e.g., "add TLS support" not "added TLS support").
- **Keep the subject line concise** (72 characters or fewer).
- **Separate subject from body** with a blank line.
- **Explain what and why** in the body, not how.

Examples:

```
add MySQL TLS environment variables for encrypted connections

Introduce MYSQL_TLS_CA, MYSQL_TLS_CERT, and MYSQL_TLS_KEY environment
variables that enable TLS for database connections. This is required for
production environments where database traffic must be encrypted.
```

```
fix permission error when running with cap_drop ALL

The /etc/freeradius directory was owned by root, causing startup failures
when all capabilities are dropped. Change ownership in the Dockerfile
to the freerad user.
```

## Reporting Issues

When opening an issue, please include:

- **Environment:** Docker version, Kubernetes version, Helm version, OS
- **Deployment method:** Docker Compose, Kubernetes manifests, or Helm chart
- **Description:** What you expected vs. what happened
- **Steps to reproduce:** Minimal steps to trigger the issue
- **Logs:** Relevant container logs (redact any secrets or credentials)
- **Configuration:** Relevant environment variables or values.yaml (redact secrets)

For security vulnerabilities, do **not** open a public issue. See [SECURITY.md](SECURITY.md) for reporting instructions.

## Keeping Deployment Methods in Sync

This project supports three deployment methods: **Docker Compose**, **Kubernetes manifests**, and **Helm chart**. When making changes, ensure all affected deployment methods are updated:

- A new environment variable must be added to `docker-compose.yaml`, the Kubernetes manifests, and the Helm chart `values.yaml`.
- A new volume mount must be reflected in all three deployment methods.
- Default value changes must be consistent across all configurations.
- Documentation (README, inline comments) must be updated for all affected methods.

Failing to keep deployment methods in sync will result in PR rejection.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold these standards. Violations may be reported to **conduct@cepatkilatteknologi.com**.

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see [LICENSE](LICENSE)).

## Questions?

If you have questions about contributing, open a discussion on GitHub or reach out to the maintainers.
