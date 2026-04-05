# FreeRADIUS 3.2.x with MySQL backend
# Using Debian trixie base with FreeRADIUS 3.2.8 from sid
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

# Add Debian sid repo for FreeRADIUS 3.2.8, pinned low so only freeradius pulls from it.
# Base system and all other packages stay on trixie (stable).
RUN echo "deb http://deb.debian.org/debian sid main" > /etc/apt/sources.list.d/sid.list \
    && printf 'Package: *\nPin: release a=unstable\nPin-Priority: 100\n' > /etc/apt/preferences.d/sid-low-priority \
    && printf 'Package: freeradius*\nPin: release a=unstable\nPin-Priority: 600\n' >> /etc/apt/preferences.d/sid-low-priority \
    && printf 'Package: libfreeradius*\nPin: release a=unstable\nPin-Priority: 600\n' >> /etc/apt/preferences.d/sid-low-priority

# Install FreeRADIUS 3.2.8 from sid, everything else from trixie.
# mariadb-client is wire-compatible with MySQL 8.4.
RUN apt-get update && apt-get install -y --no-install-recommends \
    freeradius \
    freeradius-mysql \
    freeradius-utils \
    mariadb-client \
    gosu \
    tzdata \
    && rm -f /etc/apt/sources.list.d/sid.list /etc/apt/preferences.d/sid-low-priority \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create symlink for raddb compatibility
RUN ln -sf /etc/freeradius/3.0 /etc/raddb

# Fix permissions for hardened containers (cap_drop: ALL removes DAC_OVERRIDE).
# Debian packages set /etc/freeradius to 2750 (freerad:freerad), which blocks
# root from traversing or writing when DAC_OVERRIDE is dropped. The entrypoint
# needs access during init before dropping to freerad via gosu.
# Solution: add root to freerad group + make dirs/files group-writable.
RUN usermod -aG freerad root \
    && chmod 2775 /etc/freeradius \
    && find /etc/freeradius/3.0 -type d -exec chmod 2775 {} + \
    && find /etc/freeradius/3.0 -type f -exec chmod 664 {} +

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