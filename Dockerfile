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

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates ncurses-bin && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

# Set working directory
WORKDIR /app

# Create data directory for persistence
RUN mkdir -p /app/data/cache && \
    chmod -R 777 /app/data

# Copy the release from the builder
COPY --from=builder /app/_build/prod/rel/wanderer_notifier ./

# Set environment
ENV HOME=/app

# Expose port
EXPOSE 4000

# Run the application
CMD ["./bin/wanderer_notifier", "start"]
    