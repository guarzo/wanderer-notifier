# ----------------------------------------
# 1. BUILD STAGE
# ----------------------------------------
FROM elixir:1.18-otp-27-slim AS builder

# Declare build arguments
ARG NOTIFIER_API_TOKEN
ENV NOTIFIER_API_TOKEN=$NOTIFIER_API_TOKEN

# Install build dependencies
RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

# Set working directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Copy dependency files
COPY mix.exs mix.lock ./

# Get dependencies
RUN mix deps.get --only prod

# Copy application code
COPY . .

# Compile the application and create release
RUN mix do compile, release

# ----------------------------------------
# 2. RUNTIME STAGE
# ----------------------------------------
FROM elixir:1.18-otp-27-slim

# Declare runtime environment variables
ARG NOTIFIER_API_TOKEN
ENV NOTIFIER_API_TOKEN=$NOTIFIER_API_TOKEN
ENV CONFIG_PATH=/app/etc

# Install runtime dependencies (including PostgreSQL client tools)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    ca-certificates \
    ncurses-bin \
    postgresql-client && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

# Set working directory
WORKDIR /app

# Create data directory for persistence and configuration directory
RUN mkdir -p /app/data/cache && \
    mkdir -p /app/data/backups && \
    mkdir -p /app/etc && \
    chmod -R 777 /app/data

# Create a minimal config file
RUN echo "import Config" > /app/etc/wanderer_notifier.exs

# Copy the release from the builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Copy runtime scripts
COPY scripts/start_with_db.sh /app/bin/
COPY scripts/db_operations.sh /app/bin/
RUN chmod +x /app/bin/start_with_db.sh \
    && chmod +x /app/bin/db_operations.sh

# Set environment
ENV HOME=/app

# Expose port
EXPOSE 4000

# Use the start script as entrypoint
CMD ["/app/bin/start_with_db.sh"]
    