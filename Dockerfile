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
COPY VERSION /app/version

# Get dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# ----------------------------------------
# 2. BUILDER STAGE - For application compilation
# ----------------------------------------
FROM deps AS builder

# Add build argument for API token
ARG WANDERER_NOTIFIER_API_TOKEN
ENV WANDERER_NOTIFIER_API_TOKEN=${WANDERER_NOTIFIER_API_TOKEN}

# Copy application code - core content first
COPY config config/
COPY lib lib/
COPY priv priv/

# Create the overlays directory and copy required files
RUN mkdir -p rel/overlays

COPY rel/overlays/env.bat rel/overlays/
COPY rel/overlays/env.sh rel/overlays/
COPY rel/overlays/sys.config rel/overlays/
COPY rel/overlays/wanderer_notifier.service rel/overlays/

# Copy frontend files
COPY renderer renderer/
COPY chart-service chart-service/

# Build frontend assets if they haven't been built
RUN if [ -d renderer ] && [ -f renderer/package.json ]; then \
    apt-get update && \
    apt-get install -y nodejs npm && \
    cd renderer && \
    npm ci && \
    npm run build && \
    npm run postbuild && \
    cd .. && \
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

# Get the API token from build arg
ARG WANDERER_NOTIFIER_API_TOKEN

# Set runtime environment variables
ENV LANG=C.UTF-8 \
    HOME=/app \
    MIX_ENV=prod \
    WANDERER_NOTIFIER_API_TOKEN=${WANDERER_NOTIFIER_API_TOKEN}

# Install runtime dependencies (minimal set) using BuildKit caching
RUN --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
        postgresql-client \
        openssl \
        ca-certificates \
        wget && \
    apt-get clean

# Set working directory
WORKDIR /app

# Create necessary directories with proper permissions
RUN mkdir -p /app/data/cache /app/data/backups /app/etc && \
    chmod -R 777 /app/data

# Copy the release from the builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Create static directory and copy static files
RUN mkdir -p /app/priv/static/app
COPY --from=builder /app/priv/static/app /app/priv/static/app/

# Set permissions and verify
RUN chmod -R 755 /app/priv/static/app && \
    echo "Verifying static files:" && \
    ls -la /app/priv/static/app/

# Copy only necessary runtime scripts
COPY scripts/start_with_db.sh scripts/db_operations.sh /app/bin/
RUN chmod +x /app/bin/start_with_db.sh /app/bin/db_operations.sh

# Add a robust startup wrapper script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Debug configuration\n\
echo "Starting container with command: $@" > /tmp/startup_debug.txt\n\
echo "Current directory: $(pwd)" >> /tmp/startup_debug.txt\n\
echo "Config file exists: $(test -f /app/etc/wanderer_notifier.exs && echo "yes" || echo "no")" >> /tmp/startup_debug.txt\n\
\n\
# Ensure the config file exists\n\
if [ ! -f /app/etc/wanderer_notifier.exs ]; then\n\
  echo "Creating minimal config file" >> /tmp/startup_debug.txt\n\
  echo "import Config" > /app/etc/wanderer_notifier.exs\n\
fi\n\
\n\
# Execute the original command\n\
exec "$@"' > /app/bin/validate_and_start.sh && \
chmod +x /app/bin/validate_and_start.sh

# Expose port
EXPOSE 4000

# Set health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD sh -c "wget -q -O- http://localhost:4000/health || exit 1"

# Set entrypoint to use the validation wrapper
ENTRYPOINT ["/app/bin/validate_and_start.sh"]
CMD ["/app/bin/start_with_db.sh"]
