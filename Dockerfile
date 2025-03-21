# --- Build Stage ---
FROM elixir:1.14-otp-25 AS builder

# Accept build arguments
ARG NOTIFIER_API_TOKEN
ARG APP_VERSION
ENV NOTIFIER_API_TOKEN=${NOTIFIER_API_TOKEN} \
    APP_VERSION=${APP_VERSION} \
    MIX_ENV=prod

# Install build dependencies
RUN apt-get update && \
    apt-get install -y build-essential git && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

# Copy and prepare configuration files
COPY mix.exs mix.lock ./
COPY config config
COPY chart-service chart-service
COPY rel rel
RUN chmod +x rel/overlays/env.sh && \
    mix deps.get --only prod && \
    # Inject the production token into the application configuration
    if [ -n "$NOTIFIER_API_TOKEN" ]; then \
        echo "Config setup: Using production token from build arg" && \
        echo "# Production token from build" >> config/runtime.exs && \
        echo "config :wanderer_notifier, notifier_api_token: \"$NOTIFIER_API_TOKEN\"" >> config/runtime.exs; \
    else \
        echo "WARNING: NOTIFIER_API_TOKEN is not set. The release may not work correctly."; \
    fi && \
    # Create a proper sys.config in the overlays
    echo '[' > rel/overlays/sys.config && \
    echo '  {kernel, [{distribution_mode, none}, {start_distribution, false}]},' >> rel/overlays/sys.config && \
    echo '  {nostrum, [{token, {system, "DISCORD_BOT_TOKEN"}}]}' >> rel/overlays/sys.config && \
    echo '].' >> rel/overlays/sys.config

# Build frontend and backend
COPY renderer renderer/
RUN mkdir -p priv/static/app && \
    cd renderer && npm ci && npm run build && cd .. && \
    mix deps.compile

# Compile application code
COPY lib lib
RUN mix compile --no-deps-check && \
    sed -i 's/include_executables_for: \[:unix\]/include_executables_for: \[:unix\], include_erts: false/' mix.exs && \
    # Build the release and package it
    mix release && \
    cd _build/prod/rel && tar -czf /app/release.tar.gz wanderer_notifier

# --- Runtime Stage ---
FROM elixir:1.14-otp-25-slim AS app

# Accept build argument but DON'T set it as an environment variable in the runtime container
ARG NOTIFIER_API_TOKEN

# Only set essential environment variables with default values
ENV MIX_ENV=prod \
    HOST=0.0.0.0 \
    RELEASE_DISTRIBUTION=none \
    RELEASE_NODE=none \
    ERL_EPMD_PORT=-1 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    # Default ports - these can be overridden at runtime
    PORT=4000 \
    CHART_SERVICE_PORT=3001

# Install runtime dependencies and set up locale
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl gnupg openssl libncurses5 wget procps \
    libcairo2 libpango-1.0-0 libjpeg62-turbo libgif7 libpixman-1-0 libpangomm-1.4-1v5 \
    build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
    python3 libpixman-1-dev locales && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen

WORKDIR /app

# Copy and extract the release in one step
COPY --from=builder /app/release.tar.gz /app/
COPY start.sh /app/start.sh
RUN mkdir -p /app/extracted /app/data/cache /app/chart-output && \
    tar -xzf /app/release.tar.gz -C /app/extracted && \
    mv /app/extracted/wanderer_notifier/* /app/ && \
    rm -rf /app/extracted /app/release.tar.gz && \
    chmod +x /app/bin/wanderer_notifier /app/start.sh && \
    mkdir -p /app/releases/$(find /app/releases -type d -name "[0-9]*.[0-9]*.[0-9]*" | xargs basename)/sys

# Copy chart service from the builder stage
COPY --from=builder /app/chart-service /app/chart-service/
WORKDIR /app/chart-service
RUN npm install -g node-gyp && npm install --production

# Set the working directory back to app and expose ports
WORKDIR /app
# Expose default ports - note that runtime ENV variables can change the actual ports used
EXPOSE 4000 3001

# Health check - use PORT environment variable for check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-4000}/health || exit 1

# Start the application
CMD ["/app/start.sh"]
    