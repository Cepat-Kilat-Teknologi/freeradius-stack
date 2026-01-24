FROM debian:bookworm-slim

# Install freeradius dan dependencies
RUN apt-get update -y \
  && apt-get install --no-install-recommends -y \
     freeradius \
     freeradius-mysql \
     mariadb-client \
     tzdata \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Enable SQL module and disable TLS di SQL config
RUN ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/ \
  && sed -Ei '/^[\t\s#]*tls\s+\{/, /[\t\s#]*\}/ s/^/#/' /etc/freeradius/3.0/mods-available/sql

# Create custom config directory
RUN mkdir -p /etc/freeradius/3.0/custom

# Copy entrypoint and set permissions
COPY --chmod=755 scripts/entrypoint.sh /entrypoint.sh

EXPOSE 1812/udp 1813/udp 18121/udp

# Healthcheck - uses internal status check (localhost client added by entrypoint)
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD radclient -t 3 -x 127.0.0.1:18121 status testing123 < /dev/null 2>&1 | grep -q "Received" || exit 1

ENTRYPOINT ["/entrypoint.sh"]