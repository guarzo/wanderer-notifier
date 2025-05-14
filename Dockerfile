# syntax=docker/dockerfile:1.4

# ----------------------------------------
# 0. BASE
# ----------------------------------------
FROM elixir:1.18-otp-27-slim AS base

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    HOME=/app

WORKDIR /app

# ----------------------------------------
# 1. NODE STAGE
# ----------------------------------------
FROM node:18-slim AS node_builder
WORKDIR /renderer

# Install required fonts and dependencies for canvas
RUN apt-get update && apt-get install -y --no-install-recommends \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy package files first for effective caching
COPY renderer/package*.json ./
RUN npm ci

# Copy the rest of the renderer code and build frontend assets
COPY renderer/ ./
RUN npm run build && npm run postbuild

# ----------------------------------------
# 2. DEPS STAGE
# ----------------------------------------
FROM base AS deps

# Update and install dependencies
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        git

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency files and fetch dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# ----------------------------------------
# 3. BUILDER STAGE
# ----------------------------------------
FROM deps AS builder

ARG WANDERER_NOTIFIER_API_TOKEN
ENV WANDERER_NOTIFIER_API_TOKEN=${WANDERER_NOTIFIER_API_TOKEN}

# Copy application code and configuration
COPY config config/
COPY lib lib/
COPY priv priv/
COPY rel rel/
COPY VERSION /app/version

# Copy built assets from the node stage's postbuild output (priv/static/app)
COPY --from=node_builder /renderer/dist/* /app/priv/static/app/

# Compile and build the release
RUN mix compile --warnings-as-errors && \
    mix release --overwrite

# ----------------------------------------
# 4. RUNTIME STAGE
# ----------------------------------------
FROM elixir:1.18-otp-27-slim AS runtime

ENV LANG=C.UTF-8 \
    HOME=/app \
    MIX_ENV=prod

ARG WANDERER_NOTIFIER_API_TOKEN
ENV WANDERER_NOTIFIER_API_TOKEN=${WANDERER_NOTIFIER_API_TOKEN}

# Update and install runtime packages
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        postgresql-client \
        openssl \
        ca-certificates \
        wget \
        lsof \
        net-tools \
        gnupg \
        curl \
    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the full release directory from the builder stage to /app/wanderer_notifier
COPY --from=builder /app/_build/prod/rel/wanderer_notifier /app/wanderer_notifier

# Create necessary directories with appropriate permissions
RUN mkdir -p /app/data/cache /app/data/backups /app/etc && \
    chmod -R 777 /app/data

# Copy static assets from builder (if needed)
COPY --from=builder /app/priv/static /app/priv/static

# Create start.sh script directly in the container
RUN mkdir -p /app/bin && \
    cat > /app/bin/start.sh << 'EOF'
#!/bin/bash
set -e

# Display startup information
echo "Starting Wanderer Notifier..."
echo "Elixir version: $(elixir --version | head -n 1)"
echo "Node.js version: $(node --version)"

# In production, clear token environment variables to use baked-in values
if [ "$MIX_ENV" = "prod" ]; then
  unset WANDERER_NOTIFIER_API_TOKEN
  unset NOTIFIER_API_TOKEN
fi

# Show configured ports
echo "Web server port: ${WANDERER_PORT:-4000}"

# Set default cache directory if not specified
WANDERER_CACHE_DIR=${WANDERER_CACHE_DIR:-${CACHE_DIR:-"/app/data/cache"}}

# Ensure the cache directory exists with proper permissions
echo "Ensuring cache directory exists: $WANDERER_CACHE_DIR"
mkdir -p "$WANDERER_CACHE_DIR"
chmod -R 777 "$WANDERER_CACHE_DIR"

# Source any environment variables from .env file if it exists
if [ -f .env ]; then
  echo "Loading environment from .env file"
  set -a
  source .env
  set +a
fi

# Start the main application
echo "Starting Elixir application on port ${WANDERER_PORT:-4000}..."

# Check if we have arguments (to support the previous entrypoint > cmd pattern)
if [ $# -gt 0 ]; then
  exec "$@"
else
  cd /app && exec /app/bin/wanderer_notifier start
fi
EOF
RUN chmod +x /app/bin/start.sh

# Create a symlink so that /app/bin/wanderer_notifier points to the release binary
RUN ln -s /app/wanderer_notifier/bin/wanderer_notifier /app/bin/wanderer_notifier

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -q -O- http://localhost:4000/health || exit 1

ENTRYPOINT ["/app/bin/start.sh"]
