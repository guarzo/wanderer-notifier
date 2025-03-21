#!/bin/bash
set -e

echo "System version: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "Elixir version: $(elixir --version | head -n 1)"
echo "Node.js version: $(node --version)"
echo "Current directory: $(pwd)"

# Check environment variables for the tokens
if [ -n "$NOTIFIER_API_TOKEN" ]; then
  API_TOKEN_PREFIX=$(echo "$NOTIFIER_API_TOKEN" | cut -c1-3)
  echo "DEBUG: Environment has NOTIFIER_API_TOKEN starting with: ${API_TOKEN_PREFIX}..."
else
  echo "DEBUG: Environment has NO NOTIFIER_API_TOKEN set"
fi

# Check the baked-in token in release files
BAKED_TOKEN=$(grep -r notifier_api_token /app/releases/*/runtime.exs 2>/dev/null || true)
if [ -n "$BAKED_TOKEN" ]; then
  # Extract the token from the file
  BAKED_TOKEN_VALUE=$(echo "$BAKED_TOKEN" | grep -o '"[^"]*"' | head -1 | tr -d '"')
  if [ -n "$BAKED_TOKEN_VALUE" ]; then
    BAKED_TOKEN_PREFIX=$(echo "$BAKED_TOKEN_VALUE" | cut -c1-3)
    echo "DEBUG: Baked-in token found in release files starting with: ${BAKED_TOKEN_PREFIX}..."
  else
    echo "DEBUG: Baked-in token found but could not extract value"
  fi
else
  echo "DEBUG: No baked-in token found in release files"
fi

# In production, we want to clear token environment variables
# to ensure we use the baked-in token from the release
if [ "$MIX_ENV" = "prod" ]; then
  echo "Running in production mode - clearing token environment variables to use baked-in configuration"
  unset NOTIFIER_API_TOKEN
fi

# Debug environment information
echo "MIX_ENV: ${MIX_ENV:-development}"
echo "PORT: ${PORT:-4000}"

# Check if important environment variables are set
if [ -n "$DISCORD_BOT_TOKEN" ]; then
  echo "DISCORD_BOT_TOKEN set: yes"
else
  echo "DISCORD_BOT_TOKEN set: no"
fi

if [ -n "$NOTIFIER_API_TOKEN" ]; then
  echo "NOTIFIER_API_TOKEN set: yes"
else
  echo "NOTIFIER_API_TOKEN set: no"
fi

if [ -n "$MAP_URL_WITH_NAME" ]; then
  echo "MAP_URL_WITH_NAME: $MAP_URL_WITH_NAME"
fi

# Start the chart service and main application
echo "Starting chart service..."
cd /app/assets/chart-service && npm start &
CHART_PID=$!
echo "Chart service started with PID: $CHART_PID"

echo "Starting Elixir application..."
if [ -f "/app/bin/wanderer_notifier" ]; then
  echo "Using release script"
  exec /app/bin/wanderer_notifier start
else
  echo "Using mix"
  cd /app && mix phx.server
fi
