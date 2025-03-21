# --- Build Stage ---
FROM elixir:1.14-otp-25 AS builder

# Accept build arguments
ARG NOTIFIER_API_TOKEN
ENV NOTIFIER_API_TOKEN=${NOTIFIER_API_TOKEN}

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

# Inject the production token into the application configuration
RUN if [ -n "$NOTIFIER_API_TOKEN" ]; then \
    echo "Config setup: Using production token from build arg" && \
    # Append to runtime.exs
    echo "# Production token from build" >> config/runtime.exs && \
    echo "config :wanderer_notifier, notifier_api_token: \"$NOTIFIER_API_TOKEN\"" >> config/runtime.exs && \
    # Create production token file for the release
    mkdir -p rel/overlays/etc && \
    echo "Production token: $NOTIFIER_API_TOKEN" > rel/overlays/etc/production_token.txt; \
  else \
    echo "WARNING: NOTIFIER_API_TOKEN is not set. The release may not work correctly."; \
  fi

# Create a proper sys.config in the overlays
RUN echo '[' > rel/overlays/sys.config && \
    echo '  {kernel, [{distribution_mode, none}, {start_distribution, false}]},' >> rel/overlays/sys.config && \
    echo '  {nostrum, [{token, {system, "DISCORD_BOT_TOKEN"}}]}' >> rel/overlays/sys.config && \
    echo '].' >> rel/overlays/sys.config

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

# Accept build argument but DON'T set it as an environment variable in the runtime container
# This ensures we use the baked-in value from the application config
ARG NOTIFIER_API_TOKEN
# ENV NOTIFIER_API_TOKEN=${NOTIFIER_API_TOKEN} -- REMOVED to prevent environment variable use

# Only set default values for environment variables
ENV DISCORD_BOT_TOKEN="" \
    APP_VERSION="" \
    PORT=4000 \
    HOST=0.0.0.0 \
    MIX_ENV=prod \
    CACHE_DIR=/app/data/cache \
    CHART_SERVICE_PORT=3001 \
    NOTIFIER_API_TOKEN="" \
    LICENSE_KEY="" \
    MAP_URL="" \
    MAP_URL_WITH_NAME="" \
    MAP_TOKEN="" \
    ENABLE_MAP_TOOLS=true \
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

# Create token backup files for validation/debugging
RUN mkdir -p /app/releases/token && \
  if [ -n "$NOTIFIER_API_TOKEN" ]; then \
    echo "Creating token backup files for validation..." && \
    echo "# Production token configuration" > /app/releases/token/production_config.txt && \
    echo "notifier_api_token: \"$NOTIFIER_API_TOKEN\"" >> /app/releases/token/production_config.txt; \
  else \
    echo "WARNING: No production token provided at build time" > /app/releases/token/warning.txt; \
  fi

# Ensure the token is accessible in the runtime environment by creating a backup file
RUN if [ -n "$NOTIFIER_API_TOKEN" ]; then \
    echo "Adding production token to release environment"; \
    mkdir -p /app/releases/token && \
    echo "# This file contains the production token injected during build" > /app/releases/token/production_config.txt && \
    echo "notifier_api_token: \"$NOTIFIER_API_TOKEN\"" >> /app/releases/token/production_config.txt; \
  fi

# Ensure the release executable is runnable
RUN chmod +x /app/bin/wanderer_notifier

# Remove the complex config generation and just ensure the release can find its config
RUN mkdir -p /app/releases/$(find /app/releases -type d -name "[0-9]*.[0-9]*.[0-9]*" | xargs basename)/sys

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
    