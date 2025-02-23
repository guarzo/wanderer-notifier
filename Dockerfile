# Stage 1: Build the release
FROM elixir:1.18-slim AS build

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

# Build the release (replace "your_app" with your actual app name)
RUN mix release

# Stage 2: Build the runtime image
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libncurses6 \
    libstdc++6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the release from the build stage (update "your_app" as needed)
COPY --from=build /app/_build/prod/rel/chainkills ./

# Expose the port (for a Phoenix app, typically 4000)
EXPOSE 4000

# Start the application
CMD ["bin/chainkills", "start"]

