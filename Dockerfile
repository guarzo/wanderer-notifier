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

# Copy package files first for effective caching
COPY renderer/package*.json ./
RUN npm ci

# Copy the rest of the renderer code and build frontend assets
COPY renderer/ ./
RUN npm run build && npm run postbuild

# Set up chart-service
WORKDIR /chart-service

# Copy package files first for effective caching
COPY chart-service/package*.json ./
RUN npm install

# Copy the rest of the chart-service code
COPY chart-service/ ./

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
        wget

WORKDIR /app

# Copy the full release directory from the builder stage to /app/wanderer_notifier
COPY --from=builder /app/_build/prod/rel/wanderer_notifier /app/wanderer_notifier

# Create necessary directories with appropriate permissions
RUN mkdir -p /app/data/cache /app/data/backups /app/etc && \
    chmod -R 777 /app/data

# Copy static assets from builder (if needed)
COPY --from=builder /app/priv/static /app/priv/static

# Copy chart-service from node builder
COPY --from=node_builder /chart-service /app/chart-service

# Copy runtime scripts and set executable permissions
COPY scripts/start_with_db.sh scripts/db_operations.sh /app/bin/
RUN chmod +x /app/bin/*.sh

COPY scripts/validate_and_start.sh /app/bin/validate_and_start.sh
RUN chmod +x /app/bin/validate_and_start.sh

# Create a symlink so that /app/bin/wanderer_notifier points to the release binary
RUN mkdir -p /app/bin && \
    ln -s /app/wanderer_notifier/bin/wanderer_notifier /app/bin/wanderer_notifier

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -q -O- http://localhost:4000/health || exit 1

ENTRYPOINT ["/app/bin/validate_and_start.sh"]
CMD ["/app/bin/start_with_db.sh"]
