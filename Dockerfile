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

# Install CA certificates first to fix SSL issues
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

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

# Copy application code - core content first
COPY config config/
COPY lib lib/
COPY priv priv/

# Copy frontend files
COPY renderer renderer/
COPY chart-service chart-service/

# Create the overlays directory and copy required files
RUN mkdir -p rel/overlays
COPY rel/overlays/env.bat rel/overlays/
COPY rel/overlays/env.sh rel/overlays/
COPY rel/overlays/sys.config rel/overlays/
COPY rel/overlays/wanderer_notifier.service rel/overlays/

# Debug: Verify overlays directory
RUN ls -la rel/overlays/

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
ENV NOTIFIER_CONFIG_PATH=/app/etc/wanderer_notifier.exs \
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

# Add a startup validation script to ensure CONFIG_PATH isn't duplicated
RUN echo '#!/bin/bash\n\
# Verify CONFIG_PATH is correctly set\n\
if [[ "$CONFIG_PATH" == *"/app/etc/"*"/app/etc/"* ]]; then\n\
  echo "ERROR: CONFIG_PATH contains duplicate paths: $CONFIG_PATH"\n\
  exit 1\n\
fi\n\
if [[ "$NOTIFIER_CONFIG_PATH" == *"/app/etc/"*"/app/etc/"* ]]; then\n\
  echo "ERROR: NOTIFIER_CONFIG_PATH contains duplicate paths: $NOTIFIER_CONFIG_PATH"\n\
  exit 1\n\
fi\n\
# Continue with original command\n\
exec "$@"' > /app/bin/validate_and_start.sh && \
chmod +x /app/bin/validate_and_start.sh

# Add version file
ARG APP_VERSION
RUN if [ -n "$APP_VERSION" ]; then echo "$APP_VERSION" > /app/VERSION; fi

# Expose port
EXPOSE 4000

# Set health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -q -O- http://localhost:4000/health || exit 1

# Set entrypoint to use the validation wrapper
ENTRYPOINT ["/app/bin/validate_and_start.sh"]
CMD ["/app/bin/start_with_db.sh"]
    