# Build stage - compile FreeRADIUS 3.2.8 from source
FROM debian:bookworm-slim AS builder

# FreeRADIUS version
ARG FREERADIUS_VERSION=3.2.8

# Install build dependencies
RUN apt-get update -y && apt-get install --no-install-recommends -y \
    build-essential \
    ca-certificates \
    curl \
    libssl-dev \
    libmariadb-dev \
    libtalloc-dev \
    libkqueue-dev \
    libpcre2-dev \
    libcap-dev \
    libgdbm-dev \
    libreadline-dev \
    libsqlite3-dev \
    libjson-c-dev \
    libcurl4-openssl-dev \
    libldap2-dev \
    libpam0g-dev \
    libperl-dev \
    && rm -rf /var/lib/apt/lists/*

# Download and extract FreeRADIUS source
WORKDIR /tmp
RUN curl -fsSL "https://github.com/FreeRADIUS/freeradius-server/releases/download/release_${FREERADIUS_VERSION//./_}/freeradius-server-${FREERADIUS_VERSION}.tar.gz" \
    -o freeradius.tar.gz \
    && tar -xzf freeradius.tar.gz \
    && rm freeradius.tar.gz

# Build FreeRADIUS
WORKDIR /tmp/freeradius-server-${FREERADIUS_VERSION}
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --with-mysql \
    --with-threads \
    --with-thread-pool \
    --with-openssl \
    --with-pcre2 \
    --without-rlm_eap_ikev2 \
    --without-rlm_eap_tnc \
    --without-rlm_sql_oracle \
    --without-rlm_sql_iodbc \
    && make -j$(nproc) \
    && make install DESTDIR=/freeradius-install

# Runtime stage - minimal image
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="FreeRADIUS" \
      org.opencontainers.image.description="FreeRADIUS 3.2.8 with MySQL backend" \
      org.opencontainers.image.version="3.2.8" \
      org.opencontainers.image.source="https://github.com/Cepat-Kilat-Teknologi/freeradius-stack"

# Install runtime dependencies
RUN apt-get update -y && apt-get install --no-install-recommends -y \
    libssl3 \
    libmariadb3 \
    libtalloc2 \
    libkqueue0 \
    libpcre2-8-0 \
    libcap2 \
    libgdbm6 \
    libreadline8 \
    libsqlite3-0 \
    libjson-c5 \
    libcurl4 \
    libldap-2.5-0 \
    libpam0g \
    mariadb-client \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy FreeRADIUS from builder
COPY --from=builder /freeradius-install /

# Create freerad user and group
RUN groupadd -r freerad && useradd -r -g freerad freerad

# Set correct permissions
RUN chown -R freerad:freerad /etc/raddb /var/log/radius /var/run/radiusd 2>/dev/null || true \
    && mkdir -p /etc/raddb/custom \
    && chown freerad:freerad /etc/raddb/custom

# Enable SQL module and disable TLS in SQL config
RUN ln -sf /etc/raddb/mods-available/sql /etc/raddb/mods-enabled/sql \
    && sed -Ei '/^[\t\s#]*tls\s+\{/, /[\t\s#]*\}/ s/^/#/' /etc/raddb/mods-available/sql

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
