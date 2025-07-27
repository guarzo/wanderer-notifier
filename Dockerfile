# syntax=docker/dockerfile:1.4

###############################################################################
# 1. Build Dependencies Stage with enhanced caching and optimization
###############################################################################
FROM elixir:1.18.3-otp-27-slim AS deps

WORKDIR /app

# Set Mix environment and optimization flags
ENV MIX_ENV=prod \
    ERL_FLAGS="+JPperf true +sub true +pc unicode +K true +A 64" \
    ELIXIR_ERL_OPTIONS="+fnu"

# Install build tools and optimize packages
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates \
      curl \
      xz-utils \
 && update-ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Hex and Rebar with cache mount and version pinning
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix local.hex --force \
 && mix local.rebar --force

# Copy dependency files first for better caching
COPY mix.exs mix.lock ./

# Fetch and compile dependencies with optimized cache mounts
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/app/_build,sharing=locked \
    mix deps.get --only prod \
 && mix deps.compile --force --warnings-as-errors

###############################################################################
# 2. Build Stage with optimized compilation and release
###############################################################################
FROM deps AS build

WORKDIR /app

# Accept build arguments for production optimization
ARG NOTIFIER_API_TOKEN
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Set additional build-time environment variables
ENV NOTIFIER_API_TOKEN=$NOTIFIER_API_TOKEN \
    BUILD_DATE=$BUILD_DATE \
    VCS_REF=$VCS_REF \
    VERSION=$VERSION

# Copy source code (exclusions handled by .dockerignore)
COPY . .

# Ensure Hex and Rebar are available in build stage
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix local.hex --force \
 && mix local.rebar --force

# Compile with optimizations and create release
RUN --mount=type=cache,target=/app/_build,sharing=locked \
    --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix compile --warnings-as-errors --force && \
    mix release --overwrite && \
    cp -r /app/_build/prod/rel/wanderer_notifier /app/release

###############################################################################
# 3. Runtime Stage - optimized for production
###############################################################################
FROM debian:bookworm-slim AS runtime

WORKDIR /app

# Install runtime dependencies with security and performance optimizations
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      # Core runtime dependencies
      libncurses6 \
      libstdc++6 \
      openssl \
      ca-certificates \
      libgcc-s1 \
      # Health check and monitoring tools
      curl \
      procps \
      dumb-init \
      # Locale support
      locales \
      # Security updates
 && apt-get upgrade -y \
 && echo "C.UTF-8 UTF-8" > /etc/locale.gen \
 && locale-gen \
 && groupadd -r app --gid=1000 \
 && useradd -r -g app --uid=1000 --home-dir=/app --shell=/bin/bash app \
 && mkdir -p /app/data/cache /app/logs /app/tmp \
 && chown -R app:app /app \
 && chmod 755 /app \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 && rm -rf /usr/share/doc /usr/share/man /usr/share/info

# Copy release from build stage with proper ownership
COPY --from=build --chown=app:app /app/release ./

# Accept build arguments for runtime optimization
ARG NOTIFIER_API_TOKEN
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Production runtime configuration with performance tuning
ENV REPLACE_OS_VARS=true \
    HOME=/app \
    NOTIFIER_API_TOKEN=$NOTIFIER_API_TOKEN \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm \
    # Erlang VM optimization flags:
    # +fnu: Enable filename unicode support
    # +JPperf: Enable Java-style performance counters
    # +sub: Enable sub-microsecond time resolution
    # +pc unicode: Use unicode for printable characters
    # +K: Enable kernel polling for better I/O performance
    # +A 64: Set async thread pool size to 64
    # +sbwt none: Disable scheduler bind type
    # +sbwtdcpu none: Disable dirty CPU scheduler bind type  
    # +sbwtdio none: Disable dirty I/O scheduler bind type
    ELIXIR_ERL_OPTIONS="+fnu +JPperf true +sub true +pc unicode +K true +A 64" \
    ERL_FLAGS="+JPperf true +sub true +pc unicode +K true +A 64 +sbwt none +sbwtdcpu none +sbwtdio none" \
    # Memory and GC tuning
    ERL_MAX_PORTS=65536 \
    ERL_MAX_ETS_TABLES=32768 \
    # SSL and crypto configuration
    ERL_SSL_DIST=true \
    # Process and scheduler configuration
    ERL_PROCESSES=1048576 \
    # Application directories
    CACHE_DIR=/app/data/cache \
    LOG_DIR=/app/logs \
    TMP_DIR=/app/tmp

# Security and compliance metadata
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.title="Wanderer Notifier" \
      org.opencontainers.image.description="EVE Online killmail notification service" \
      org.opencontainers.image.vendor="Wanderer Project" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/wanderer-industries/wanderer-notifier"

# Set proper file permissions and create volume mount points
RUN chmod +x /app/bin/wanderer_notifier \
 && mkdir -p /app/data/cache /app/logs \
 && chown -R app:app /app/data /app/logs

# Create volume for persistent data
VOLUME ["/app/data", "/app/logs"]

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4000/api/health || exit 1

# Switch to non-root user for security
USER app

# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["bin/wanderer_notifier", "start"]


# Expose default port
EXPOSE 4000

# Add security labels for container scanning
LABEL security.scan.enabled=true \
      security.scan.policy="strict"