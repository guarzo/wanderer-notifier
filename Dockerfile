# Build stage
FROM elixir:1.14.5-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base git

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy config files first
COPY config config

# Copy release files and ensure correct permissions
COPY rel rel
RUN chmod +x rel/overlays/env.sh

# Copy templates
COPY lib/wanderer_notifier/web/templates priv/templates

# Copy static files (React app)
COPY priv/static priv/static

# Compile dependencies with Nostrum config
RUN mix deps.compile

# Copy application code
COPY lib lib

# Compile the project
RUN mix compile --no-deps-check

# Build release
RUN mix release

# Run stage
FROM alpine:3.18.2 AS app

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs libstdc++ bash wget

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Create directory for runtime environment file and data
RUN mkdir -p /app/etc /app/data/cache

# Create a non-root user
RUN adduser -D wanderer
RUN chown -R wanderer:wanderer /app
USER wanderer

# Set default environment variables (can be overridden)
ENV PORT=8080 \
    HOST=0.0.0.0 \
    MIX_ENV=prod \
    CACHE_DIR=/app/data/cache

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:$PORT/health || exit 1

EXPOSE $PORT

# Start application
CMD ["/app/bin/wanderer_notifier", "start"] 