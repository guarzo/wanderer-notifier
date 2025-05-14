# syntax=docker/dockerfile:experimental

###############################################################################
# 1. Dependencies Stage
###############################################################################
FROM elixir:1.18.3-otp-27-slim AS deps

WORKDIR /app

# Install build tools
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       build-essential \
       git \
       ca-certificates \
  && update-ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Copy and fetch only prod deps (cached)
COPY mix.exs mix.lock ./
RUN mix local.hex --force \
  && mix local.rebar --force \
  && mix deps.get --only prod \
  && mix deps.compile

###############################################################################
# 2. Build Stage
###############################################################################
FROM deps AS build

ENV MIX_ENV=prod

# Install Node.js for asset compilation
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       curl \
       ca-certificates \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

# 2a. Frontend: cache npm install
WORKDIR /app/renderer
COPY renderer/package.json renderer/package-lock.json ./
RUN npm ci

# 2b. Frontend: build assets
COPY renderer/. ./
RUN npm run build && npm run postbuild

# 2c. Compile & release **without** bundling ERTS
WORKDIR /app
COPY . .
RUN mix compile --warnings-as-errors \
 && mix release --overwrite

###############################################################################
# 3. Runtime Stage (Elixir slim)
###############################################################################
FROM elixir:1.18-otp-27-slim AS runtime

WORKDIR /app

# Install wget for health‐checks
RUN apt-get update \
  && apt-get install -y --no-install-recommends wget \
  && rm -rf /var/lib/apt/lists/* \
  && addgroup --system app \
  && adduser --system --ingroup app app

# Copy the contents of your release
COPY --from=build --chown=app:app /app/_build/prod/rel/wanderer_notifier/. ./

# Allow runtime config via ENV
ENV REPLACE_OS_VARS=true \
    HOME=/app

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.version=$VERSION

# Switch to non-root user
USER app

ENTRYPOINT ["bin/wanderer_notifier"]
CMD ["start"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:4000/health || exit 1
