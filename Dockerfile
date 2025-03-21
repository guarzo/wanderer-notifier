# ----------------------------------------
# 1. BUILD STAGE
# ----------------------------------------
    FROM elixir:1.14-otp-25 AS builder

    # Accept build arguments
    ARG NOTIFIER_API_TOKEN
    ARG APP_VERSION
    
    # Set environment variables for the build
    ENV NOTIFIER_API_TOKEN=${NOTIFIER_API_TOKEN} \
        APP_VERSION=${APP_VERSION} \
        MIX_ENV=prod
    
    # Install build dependencies
    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            build-essential \
            git \
            curl \
            gnupg \
            openssl \
            wget \
            # the following for node
            ca-certificates \
        && rm -rf /var/lib/apt/lists/*
    
    # Install Node.js (needed for building frontend assets)
    # Using a single RUN step allows Docker to cache it properly
    RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get update && \
        apt-get install -y --no-install-recommends nodejs && \
        rm -rf /var/lib/apt/lists/*
    
    # Install Elixir dependencies
    RUN mix local.hex --force && \
        mix local.rebar --force
    
    WORKDIR /app
    
    # -------------
    # Copy mix files and fetch deps first for better caching
    # -------------
    COPY mix.exs mix.lock ./
    # Copy only the configuration that's needed to compile dependencies
    COPY config config
    
    RUN mix deps.get --only prod
    
    # -------------
    # Copy the rest of the source
    # -------------
    COPY chart-service chart-service
    COPY rel rel
    COPY renderer renderer/
    COPY lib lib
    
    # -------------
    # Environment- or token-specific steps
    # -------------
    # If you want to "bake in" the token at build time:
    RUN if [ -n "$NOTIFIER_API_TOKEN" ]; then \
          echo "Config setup: Using production token from build arg" && \
          echo "# Production token from build" >> config/runtime.exs && \
          echo "config :wanderer_notifier, notifier_api_token: \"$NOTIFIER_API_TOKEN\"" >> config/runtime.exs; \
        else \
          echo "WARNING: NOTIFIER_API_TOKEN is not set. The release may not work correctly."; \
        fi && \
        chmod +x rel/overlays/env.sh
    
    # -------------
    # Adjust sys.config
    # -------------
    RUN echo '[' > rel/overlays/sys.config && \
        echo '  {kernel, [{distribution_mode, none}, {start_distribution, false}]},' >> rel/overlays/sys.config && \
        echo '  {nostrum, [{token, {system, "DISCORD_BOT_TOKEN"}}]}' >> rel/overlays/sys.config && \
        echo '].' >> rel/overlays/sys.config
    
    # -------------
    # Build assets
    # -------------
    RUN mkdir -p priv/static/app && \
        cd renderer && \
        npm ci && \
        npm run build
    
    # -------------
    # Install chart service dependencies in the build stage
    # -------------
    WORKDIR /app/chart-service
    RUN npm ci --only=production || npm install --production
    
    # -------------
    # Compile and build release - make sure we're in the main app directory
    # -------------
    WORKDIR /app
    RUN mix deps.compile && \
        # Toggle ERTS inclusion if you prefer to rely on the final container's OTP
        sed -i 's/include_executables_for: \[:unix\]/include_executables_for: \[:unix\], include_erts: false/' mix.exs && \
        mix compile --no-deps-check && \
        mix release && \
        cd _build/prod/rel && \
        tar -czf /app/release.tar.gz wanderer_notifier
    
    # ----------------------------------------
    # 2. RUNTIME STAGE
    # ----------------------------------------
    FROM elixir:1.14-otp-25-slim AS app
    
    # Accept build argument but DO NOT set as an ENV variable
    ARG NOTIFIER_API_TOKEN
    
    # Set essential environment variables
    ENV MIX_ENV=prod \
        HOST=0.0.0.0 \
        RELEASE_DISTRIBUTION=none \
        RELEASE_NODE=none \
        ERL_EPMD_PORT=-1 \
        LANG=en_US.UTF-8 \
        LANGUAGE=en_US:en \
        LC_ALL=en_US.UTF-8 \
        PORT=4000 \
        CHART_SERVICE_PORT=3001
    
    # Install runtime dependencies including Node.js
    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
          curl \
          gnupg \
          openssl \
          libncurses5 \
          procps \
          libcairo2 \
          libpango-1.0-0 \
          libjpeg62-turbo \
          libgif7 \
          libpixman-1-0 \
          libpangomm-1.4-1v5 \
          locales \
          wget \
        && rm -rf /var/lib/apt/lists/*
    
    # Install Node.js for the runtime - simpler approach
    RUN apt-get update && \
        apt-get install -y --no-install-recommends gnupg curl ca-certificates && \
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get update && \
        apt-get install -y --no-install-recommends nodejs && \
        rm -rf /var/lib/apt/lists/* && \
        node --version && \
        npm --version
    
    # Enable locale
    RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
        locale-gen
    
    WORKDIR /app
    
    # -------------
    # Copy the release tar from builder
    # -------------
    COPY --from=builder /app/release.tar.gz /app/release.tar.gz
    COPY start.sh /app/start.sh
    
    RUN mkdir -p /app/extracted /app/data/cache /app/chart-output && \
        tar -xzf /app/release.tar.gz -C /app/extracted && \
        mv /app/extracted/wanderer_notifier/* /app/ && \
        rm -rf /app/extracted /app/release.tar.gz && \
        chmod +x /app/bin/wanderer_notifier /app/start.sh
    
    # ----------------------------------------
    # CHART SERVICE SETUP - Copy with pre-installed node_modules, but verify Node.js availability
    # ----------------------------------------
    # Copy chart-service including pre-installed node_modules
    COPY --from=builder /app/chart-service /app/chart-service
    WORKDIR /app/chart-service

    # Verify Node.js is available in the runtime environment
    RUN node --version && npm --version && \
        echo "Node.js and npm verified in chart-service directory"

    # -------------
    # Set final working directory and ports
    # -------------
    WORKDIR /app
    EXPOSE 4000 3001
    
    # -------------
    # Health check
    # -------------
    HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
      CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-4000}/health || exit 1
    
    # -------------
    # Run as non-root user (if desired)
    # -------------
    # RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
    # USER appuser
    
    # -------------
    # Final start command
    # -------------
    CMD ["/app/start.sh"]
    