FROM elixir:1.18-otp-27-slim AS base

# Set common environment variables
ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    HOME=/app

# Create common directories
WORKDIR /app

# ----------------------------------------
# 1. DEPS STAGE - Just for dependency installation
# ----------------------------------------
FROM base AS deps

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install build dependencies
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Only copy dependency files
COPY mix.exs mix.lock ./

# Get dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# ----------------------------------------
# 2. BUILDER STAGE - For application compilation
# ----------------------------------------
FROM deps AS builder

# Declare build argument for version and other environment variables
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

# Copy application code
COPY config config/
COPY lib lib/
COPY priv priv/
COPY renderer renderer/
COPY chart-service chart-service/

# Build frontend assets if they haven't been built
RUN if [ -d renderer ] && [ -f renderer/package.json ]; then \
    apt-get update && \
    apt-get install -y nodejs npm && \
    cd renderer && npm ci && npm run build && cd .. && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Compile and build release
RUN mix compile --warnings-as-errors && \
    mix release --overwrite

# ----------------------------------------
# 3. RUNTIME STAGE - Minimal image for running the application
# ----------------------------------------
FROM elixir:1.18-otp-27-slim AS runtime

# Set runtime environment variables
ENV CONFIG_PATH=/app/etc \
    LANG=C.UTF-8 \
    HOME=/app

# Install runtime dependencies (minimal set)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        postgresql-client \
        openssl \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Create necessary directories with proper permissions
RUN mkdir -p /app/data/cache \
    /app/data/backups \
    /app/etc && \
    chmod -R 777 /app/data

# Create a minimal config file
RUN echo "import Config" > /app/etc/wanderer_notifier.exs

# Copy the release from the builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Copy only necessary runtime scripts
COPY scripts/start_with_db.sh scripts/db_operations.sh /app/bin/
RUN chmod +x /app/bin/start_with_db.sh /app/bin/db_operations.sh

# Add version file
ARG APP_VERSION
RUN if [ -n "$APP_VERSION" ]; then echo "$APP_VERSION" > /app/VERSION; fi

# Expose port
EXPOSE 4000

# Set health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -q -O- http://localhost:4000/health || exit 1

# Set entrypoint
CMD ["/app/bin/start_with_db.sh"]
    