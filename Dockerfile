# --- Build Stage ---
FROM elixir:1.14-otp-25 AS builder

# Accept build arguments
ARG WANDERER_PRODUCTION_BOT_TOKEN
ENV WANDERER_PRODUCTION_BOT_TOKEN=${WANDERER_PRODUCTION_BOT_TOKEN}

ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

# Install build dependencies
RUN apt-get update && \
    apt-get install -y build-essential git && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy configuration and service files
COPY config config
COPY chart-service chart-service
COPY rel rel
RUN chmod +x rel/overlays/env.sh

# Create a custom sys.config that reads from environment variables
RUN echo '[{nostrum, [{token, "${DISCORD_BOT_TOKEN}"}]}].' > rel/overlays/sys.config

# Ensure necessary directories exist
RUN mkdir -p priv/static/app

# Build the frontend
COPY renderer renderer/
RUN cd renderer && npm ci && npm run build

# Compile dependencies and application code
RUN mix deps.compile
COPY lib lib
RUN mix compile --no-deps-check

# Update mix.exs to disable including ERTS (if appropriate)
RUN sed -i 's/include_executables_for: \[:unix\]/include_executables_for: \[:unix\], include_erts: false/' mix.exs

# Build the release and package it as a tar file
RUN mix release && \
    cd _build/prod/rel && tar -czf /app/release.tar.gz wanderer_notifier

# --- Runtime Stage ---
FROM elixir:1.14-otp-25 AS app

# Only set default values for environment variables
ENV DISCORD_BOT_TOKEN="" \
    APP_VERSION="" \
    PORT=4000 \
    HOST=0.0.0.0 \
    MIX_ENV=prod \
    CACHE_DIR=/app/data/cache \
    CHART_SERVICE_PORT=3001 \
    ERL_LIBS="" \
    ELIXIR_ERL_OPTIONS="" \
    RELEASE_DISTRIBUTION=none \
    RELEASE_NODE=none \
    ERL_EPMD_PORT=-1

# Install runtime dependencies including Node.js
RUN apt-get update && \
    apt-get install -y curl gnupg openssl libncurses5 wget procps \
    libcairo2 libpango-1.0-0 libjpeg62-turbo libgif7 libpixman-1-0 libpangomm-1.4-1v5 \
    build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev python3 libpixman-1-dev locales && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

# Copy and extract the release
COPY --from=builder /app/release.tar.gz /app/
RUN mkdir -p /app/extracted && \
    tar -xzf /app/release.tar.gz -C /app/extracted && \
    mv /app/extracted/wanderer_notifier/* /app/ && \
    rm -rf /app/extracted /app/release.tar.gz

# Ensure the release executable is runnable
RUN chmod +x /app/bin/wanderer_notifier

# Use our custom sys.config - remove the line that would override it
# RUN find /app/releases -type d -name "*.*.*" -exec sh -c 'echo "[{kernel, [{distribution_mode, none}, {start_distribution, false}]}]." > {}/sys.config' \;

# Instead, use the one we created earlier
COPY --from=builder /app/rel/overlays/sys.config /app/releases/sys.config

# Set up chart service
COPY --from=builder /app/chart-service /app/chart-service/
WORKDIR /app/chart-service
RUN npm install -g node-gyp && npm install --production

WORKDIR /app
# Copy an external startup script (see below)
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Create necessary directories
RUN mkdir -p /app/data/cache /app/chart-output

# Expose ports for web server and chart service
EXPOSE 4000 3001

# Health check (adjust as needed)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1

# Start the application
CMD ["/app/start.sh"]
    