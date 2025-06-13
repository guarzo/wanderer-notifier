# syntax=docker/dockerfile:1.4

###############################################################################
# 1. Build Dependencies Stage with enhanced caching
###############################################################################
FROM elixir:1.18.3-otp-27-slim AS deps

WORKDIR /app

# Set Mix environment
ENV MIX_ENV=prod

# Install build tools
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Install Hex and Rebar with cache mount
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix local.hex --force \
 && mix local.rebar --force

# Copy dependency files first
COPY mix.exs mix.lock ./

# Fetch and compile dependencies with cache mounts
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/app/_build,sharing=locked \
    mix deps.get --only prod \
 && mix deps.compile

###############################################################################
# 2. Build Stage with build cache
###############################################################################
FROM deps AS build

WORKDIR /app

# Copy source code
COPY . .

# Compile and release with cache mount for build artifacts
RUN --mount=type=cache,target=/app/_build,sharing=locked \
    mix compile --warnings-as-errors \
 && mix release --overwrite \
 && cp -r /app/_build/prod/rel/wanderer_notifier /app/release

###############################################################################
# 3. Runtime Stage - minimal size
###############################################################################
FROM debian:bookworm-slim AS runtime

WORKDIR /app

# Install runtime dependencies in one layer
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libncurses6 \
      libstdc++6 \
      openssl \
      ca-certificates \
      libgcc-s1 \
      wget \
      procps \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -r app \
 && useradd -r -g app app

# Copy release from build stage
COPY --from=build --chown=app:app /app/release ./

# Runtime configuration
ENV REPLACE_OS_VARS=true \
    HOME=/app

# Metadata
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION

# Run as non-root
USER app

# Entry point
ENTRYPOINT ["bin/wanderer_notifier"]
CMD ["start"]

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1