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
    MIX_ENV=prod \
    ERL_CRASH_DUMP_SECONDS=0 \
    ERL_AFLAGS="-kernel shell_history enabled" \
    ELIXIR_ERL_OPTIONS="-kernel standard_io_encoding latin1" \
    # Default test values for required environment variables
    WANDERER_MAP_TOKEN="changeme" \
    WANDERER_NOTIFIER_API_TOKEN="changeme" \
    WANDERER_DISCORD_BOT_TOKEN="changeme" \
    WANDERER_LICENSE_KEY="changeme" \
    WANDERER_MAP_URL="http://example.com/map?name=changeme" \
    WANDERER_DISCORD_CHANNEL_ID="123456789" \
    WANDERER_LICENSE_MANAGER_URL="http://example.com/license-manager"

ARG WANDERER_NOTIFIER_API_TOKEN
ENV WANDERER_NOTIFIER_API_TOKEN=${WANDERER_NOTIFIER_API_TOKEN:-changeme}

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

# Copy runtime script and set executable permissions
COPY ./scripts/start.sh /app/bin/start.sh
RUN chmod +x /app/bin/*.sh

# Create a symlink so that /app/bin/wanderer_notifier points to the release binary
RUN mkdir -p /app/bin && \
    ln -s /app/wanderer_notifier/bin/wanderer_notifier /app/bin/wanderer_notifier

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -q -O- http://localhost:4000/health || exit 1

ENTRYPOINT ["/app/bin/start.sh"]
