# Build stage
FROM elixir:1.15-alpine AS builder

# Accept build arguments
ARG WANDERER_PRODUCTION_BOT_TOKEN
ENV WANDERER_PRODUCTION_BOT_TOKEN=${WANDERER_PRODUCTION_BOT_TOKEN}

# Accept version argument
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

# Install build dependencies
RUN apk add --no-cache build-base git npm nodejs

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

# Ensure directories exist
RUN mkdir -p priv/static/app

# Copy renderer code and build frontend
COPY renderer renderer/
RUN cd renderer && npm ci && npm run build

# Compile dependencies
RUN mix deps.compile

# Copy application code
COPY lib lib

# Compile the project
RUN mix compile --no-deps-check

# Build release
RUN mix release

# Runtime stage
FROM node:20-alpine AS app

# Pass build arguments to runtime
ARG WANDERER_PRODUCTION_BOT_TOKEN
ENV WANDERER_PRODUCTION_BOT_TOKEN=${WANDERER_PRODUCTION_BOT_TOKEN}

# Pass version argument to runtime
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs libstdc++ bash wget

# Install Node.js canvas dependencies
RUN apk add --no-cache \
    cairo \
    pango \
    libjpeg-turbo \
    giflib \
    pixman \
    pangomm \
    libjpeg

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Copy chart service files
COPY --from=builder /app/renderer/chart-service chart-service/
COPY --from=builder /app/renderer/package.json ./
COPY --from=builder /app/renderer/package-lock.json ./

# Install Node.js dependencies for chart service
RUN npm ci --production

# Create directory for runtime environment file and data
RUN mkdir -p /app/etc /app/data/cache /app/chart-output

# Create a startup script
RUN echo '#!/bin/sh\n\
# Start the chart service in background\n\
node /app/chart-service/chart-generator.js &\n\
\n\
# Start the Elixir application\n\
exec /app/bin/wanderer_notifier start\n\
' > /app/start.sh && chmod +x /app/start.sh

# Create a non-root user
RUN adduser -D wanderer
RUN chown -R wanderer:wanderer /app
USER wanderer

# Set default environment variables (can be overridden)
ENV PORT=8080 \
    HOST=0.0.0.0 \
    MIX_ENV=prod \
    CACHE_DIR=/app/data/cache \
    CHART_SERVICE_PORT=3001

# Expose ports for web server and chart service
EXPOSE $PORT 3001

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:$PORT/health || exit 1

# Start application
CMD ["/app/start.sh"]