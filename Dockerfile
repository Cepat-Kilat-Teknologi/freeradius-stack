# FreeRADIUS 3.2.x with MySQL backend
# Using Debian trixie official packages
# For reproducible builds, pin the digest:
# ARG from=debian:trixie-slim@sha256:<digest>
ARG from=debian:trixie-slim
FROM ${from}

ARG DEBIAN_FRONTEND=noninteractive
ARG IMAGE_VERSION=3.2.8

LABEL org.opencontainers.image.title="FreeRADIUS" \
      org.opencontainers.image.description="FreeRADIUS 3.2.x with MySQL backend" \
      org.opencontainers.image.source="https://github.com/Cepat-Kilat-Teknologi/freeradius-stack" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

# Create freerad user and group with specific IDs
ARG freerad_uid=101
ARG freerad_gid=101

RUN groupadd -g ${freerad_gid} -r freerad \
    && useradd -u ${freerad_uid} -g freerad -r -M -d /etc/freeradius -s /usr/sbin/nologin freerad

# Install FreeRADIUS and dependencies from Debian official repo
# Note: mariadb-client is the correct choice on Debian -- mysql-client is a
# transitional package. mariadb-client is wire-compatible with MySQL 8.4.
RUN apt-get update && apt-get install -y --no-install-recommends \
    freeradius \
    freeradius-mysql \
    freeradius-utils \
    mariadb-client \
    gosu \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create symlink for raddb compatibility
RUN ln -sf /etc/freeradius/3.0 /etc/raddb

# Copy entrypoint and set permissions
COPY --link --chmod=755 scripts/entrypoint.sh /entrypoint.sh

EXPOSE 1812/udp 1813/udp

# Healthcheck secret (internal use only, localhost binding)
# IMPORTANT: Override this with a secure value in production
# This default is intentionally weak to remind users to change it
ENV HEALTHCHECK_SECRET=testing123

# Healthcheck - uses internal status check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD echo "Message-Authenticator = 0x00" | radclient -t 3 127.0.0.1:18121 status ${HEALTHCHECK_SECRET} 2>&1 | grep -q "Received" || exit 1

# Graceful shutdown
STOPSIGNAL SIGTERM

ENTRYPOINT ["/entrypoint.sh"]