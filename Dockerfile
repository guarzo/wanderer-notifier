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
RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Create directory for runtime environment file
RUN mkdir -p /app/etc

# Create a non-root user
RUN adduser -D wanderer
RUN chown -R wanderer:wanderer /app
USER wanderer

# Set default environment variables (can be overridden)
ENV PORT=4000 \
    HOST=0.0.0.0

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
  CMD nc -z localhost $PORT || exit 1

EXPOSE $PORT

# Start application
CMD ["/app/bin/wanderer_notifier", "start"] 