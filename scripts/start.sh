#!/bin/bash
set -e

# Set OTP environment variables to improve stability
export ERL_CRASH_DUMP_SECONDS=0
export ERL_AFLAGS="-kernel shell_history enabled"

# Display startup information
echo "Starting Wanderer Notifier..." >/proc/1/fd/1 2>/proc/1/fd/2
echo "Elixir version: $(elixir --version 2>/dev/null | head -n 1 || echo "version check failed")" >/proc/1/fd/1 2>/proc/1/fd/2
echo "Node.js version: $(node --version 2>/dev/null || echo "version check failed")" >/proc/1/fd/1 2>/proc/1/fd/2

# In production, clear token environment variables to use baked-in values
if [ "$MIX_ENV" = "prod" ]; then
  unset WANDERER_NOTIFIER_API_TOKEN
  unset NOTIFIER_API_TOKEN
fi

# Show configured ports
echo "Web server port: ${WANDERER_PORT:-4000}" >/proc/1/fd/1 2>/proc/1/fd/2

# Set default cache directory if not specified
WANDERER_CACHE_DIR=${WANDERER_CACHE_DIR:-${CACHE_DIR:-"/app/data/cache"}}

# Ensure the cache directory exists with proper permissions
echo "Ensuring cache directory exists: $WANDERER_CACHE_DIR" >/proc/1/fd/1 2>/proc/1/fd/2
mkdir -p "$WANDERER_CACHE_DIR"
chmod -R 777 "$WANDERER_CACHE_DIR"

# Source any environment variables from .env file if it exists
if [ -f .env ]; then
  echo "Loading environment from .env file" >/proc/1/fd/1 2>/proc/1/fd/2
  set -a
  source .env
  set +a
fi

# Start the main application
echo "Starting Elixir application on port ${WANDERER_PORT:-4000}..." >/proc/1/fd/1 2>/proc/1/fd/2

# Check if we have arguments (to support the previous entrypoint > cmd pattern)
if [ $# -gt 0 ]; then
  exec "$@"
else
  cd /app && exec /app/bin/wanderer_notifier start
fi
