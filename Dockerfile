# FreeRADIUS 3.2.x with MySQL backend
# Using Debian trixie official packages
ARG from=debian:trixie-slim
FROM ${from}

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="FreeRADIUS" \
      org.opencontainers.image.description="FreeRADIUS 3.2.x with MySQL backend" \
      org.opencontainers.image.source="https://github.com/Cepat-Kilat-Teknologi/freeradius-stack"

# Create freerad user and group with specific IDs
ARG freerad_uid=101
ARG freerad_gid=101

RUN groupadd -g ${freerad_gid} -r freerad \
    && useradd -u ${freerad_uid} -g freerad -r -M -d /etc/freeradius -s /usr/sbin/nologin freerad

# Install FreeRADIUS and dependencies from Debian official repo
RUN apt-get update && apt-get install -y --no-install-recommends \
    freeradius \
    freeradius-mysql \
    freeradius-utils \
    mariadb-client \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create symlink for raddb compatibility
RUN ln -sf /etc/freeradius/3.0 /etc/raddb

# Copy entrypoint and set permissions
COPY --chmod=755 scripts/entrypoint.sh /entrypoint.sh

EXPOSE 1812/udp 1813/udp 18121/udp

# Healthcheck secret (internal use only, localhost binding)
ENV HEALTHCHECK_SECRET=testing123

# Healthcheck - uses internal status check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD radclient -t 3 -x 127.0.0.1:18121 status ${HEALTHCHECK_SECRET} < /dev/null 2>&1 | grep -q "Received" || exit 1

# Graceful shutdown
STOPSIGNAL SIGTERM

ENTRYPOINT ["/entrypoint.sh"]