# syntax=docker/dockerfile:experimental

###############################################################################
# 1. Build Dependencies Stage
#
#    - Installs build tools, pulls in Elixir, fetches & compiles production deps.
#    - Uses cache mounts for Hex/Rebar and Mix builds to speed up rebuilds.
###############################################################################
FROM elixir:1.18.3-otp-27-slim AS deps

WORKDIR /app

# Set Mix environment and a default application version (overridable via build-arg)
ENV MIX_ENV=prod \
    APP_VERSION=0.1.0-docker

# Install only the build tools we need
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Install Hex and Rebar (for dependency resolution)
RUN mix local.hex --force \
 && mix local.rebar --force

# Copy only mix.exs and mix.lock to leverage Docker layer caching
COPY mix.exs mix.lock ./

# Fetch and compile production dependencies, using cache mounts to speed rebuilds
RUN --mount=type=cache,target=/root/.cache/mix \
    --mount=type=cache,target=/root/.cache/rebar \
    mix deps.get --only prod \
 && mix deps.compile

###############################################################################
# 2. Build Stage
#
#    - Copies the entire source tree, compiles the application, and builds a release.
###############################################################################
FROM deps AS build

WORKDIR /app

# Propagate the app version into the build
ARG APP_VERSION=0.1.0-docker
ENV APP_VERSION=${APP_VERSION}

# Copy the rest of the application code
COPY . .

# Compile the app (fail on any warnings) and build the OTP release
RUN mix compile --warnings-as-errors \
 && mix release --overwrite

###############################################################################
# 3. Runtime Stage
#
#    - Starts from a fresh Elixir slim image.
#    - Installs only what’s needed at runtime (wget for health checks and CA certs).
#    - Copies the compiled release and switches to a non-root user.
###############################################################################
FROM elixir:1.18.3-otp-27-slim AS runtime

WORKDIR /app

# Install runtime dependencies (wget for health checks, ca-certificates for HTTPS)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      wget \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && addgroup --system app \
 && adduser --system --ingroup app app

# Copy the built release from the build stage, with ownership set to the 'app' user
COPY --from=build --chown=app:app /app/_build/prod/rel/wanderer_notifier ./

# Allow runtime configuration via environment variables
ENV REPLACE_OS_VARS=true \
    HOME=/app

# Labels for container metadata
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION

# Drop to non-root user for safety
USER app

# Define entrypoint and default command to start the release
ENTRYPOINT ["bin/wanderer_notifier"]
CMD ["start"]

# Simple HTTP health check on port 4000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1
