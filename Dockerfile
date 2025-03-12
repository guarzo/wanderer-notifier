# Stage 1: Build the release
FROM hexpm/elixir:1.18.0-erlang-26.2.1-ubuntu-23.10-20231211 AS build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    npm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set environment to production
ENV MIX_ENV=prod

# Set the working directory
WORKDIR /app

# Copy mix files and fetch dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy the rest of the application code
COPY . .

# Build the release
RUN mix release

# Stage 2: Build the runtime image
FROM ubuntu:23.10

# Create non-root user for runtime
RUN useradd -ms /bin/bash appuser

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    libncurses6 \
    libstdc++6 \
    curl \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the release from the build stage
COPY --from=build /app/_build/prod/rel/wanderer_notifier ./

# Change ownership of the release directory
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose the port (if applicable)
EXPOSE 8080

# Optional: add a healthcheck to monitor container health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -fs http://localhost:8080/ || exit 1

# Start the application
CMD ["bin/wanderer_notifier", "start"]
