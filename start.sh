#!/bin/sh
echo "=== Starting Wanderer Notifier ==="

# Check our environment
echo "System version: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Elixir version: $(elixir --version | head -1)"
echo "Node.js version: $(node --version)"
echo "Current directory: $(pwd)"

# Minimal token debugging - only show first 3 chars
if [ -n "$WANDERER_PRODUCTION_BOT_TOKEN" ]; then
  ENV_TOKEN_PREFIX=$(echo "$WANDERER_PRODUCTION_BOT_TOKEN" | cut -c1-3)
  echo "DEBUG: Environment has WANDERER_PRODUCTION_BOT_TOKEN starting with: ${ENV_TOKEN_PREFIX}..."
else
  echo "DEBUG: Environment has NO WANDERER_PRODUCTION_BOT_TOKEN set"
fi

if [ -n "$BOT_API_TOKEN" ]; then
  API_TOKEN_PREFIX=$(echo "$BOT_API_TOKEN" | cut -c1-3)
  echo "DEBUG: Environment has BOT_API_TOKEN starting with: ${API_TOKEN_PREFIX}..."
else
  echo "DEBUG: Environment has NO BOT_API_TOKEN set"
fi

# Check the baked-in token file
BAKED_TOKEN_LINE=$(grep "production_bot_token:" /app/releases/*/runtime.exs | tail -1)
if [ -n "$BAKED_TOKEN_LINE" ]; then
  # Extract the token value - assumes format: production_bot_token: "TOKEN"
  BAKED_TOKEN=$(echo "$BAKED_TOKEN_LINE" | sed 's/.*production_bot_token: "\([^"]*\)".*/\1/')
  if [ -n "$BAKED_TOKEN" ]; then
    BAKED_PREFIX=$(echo "$BAKED_TOKEN" | cut -c1-3)
    echo "DEBUG: Baked-in token found in release files starting with: ${BAKED_PREFIX}..."
  else
    echo "DEBUG: Could not extract baked-in token value from: $BAKED_TOKEN_LINE"
  fi
else
  echo "DEBUG: No baked-in token found in release files"
fi

# In production mode, we don't use environment variables for security
# The token should be baked into the release
if [ "$MIX_ENV" = "prod" ]; then
  # Force use of baked-in token by unsetting environment variables in production
  echo "Running in production mode - clearing token environment variables to use baked-in configuration"
  # Unset the environment variables to ensure we use the baked-in values
  unset WANDERER_PRODUCTION_BOT_TOKEN
  unset BOT_API_TOKEN
else
  # Only in development/test environments
  if [ -z "$BOT_API_TOKEN" ] && [ -n "$WANDERER_PRODUCTION_BOT_TOKEN" ]; then
    echo "Setting BOT_API_TOKEN from WANDERER_PRODUCTION_BOT_TOKEN (development only)"
    export BOT_API_TOKEN="$WANDERER_PRODUCTION_BOT_TOKEN"
  fi
fi

# Debug some key environment variables
echo "MIX_ENV: $MIX_ENV"
echo "PORT: $PORT"
if [ -n "$DISCORD_BOT_TOKEN" ]; then
  echo "DISCORD_BOT_TOKEN set: yes"
else
  echo "DISCORD_BOT_TOKEN set: no"
fi

# Don't log token information in production
if [ "$MIX_ENV" != "prod" ]; then
  if [ -n "$BOT_API_TOKEN" ]; then
    echo "BOT_API_TOKEN set: yes"
  else
    echo "BOT_API_TOKEN set: no"
  fi
fi

if [ -n "$MAP_URL_WITH_NAME" ]; then
  echo "MAP_URL_WITH_NAME: $MAP_URL_WITH_NAME"
else
  echo "MAP_URL_WITH_NAME: (not set)"
fi

echo "Starting chart service..."
cd /app/chart-service && node chart-generator.js &
CHART_PID=$!
echo "Chart service started with PID: $CHART_PID"

echo "Starting Elixir application..."
cd /app

# Check if the release script exists
if [ -x "/app/bin/wanderer_notifier" ]; then
  echo "Using release script"
  RELEASE_DISTRIBUTION=none RELEASE_NODE=none bin/wanderer_notifier start
else
  echo "Error: Release script not found or not executable"
  echo "Files in bin directory:"
  ls -la /app/bin/ || echo "No bin directory"
  exit 1
fi
