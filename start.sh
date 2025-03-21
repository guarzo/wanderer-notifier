#!/bin/sh
echo "=== Starting Wanderer Notifier ==="

# Check our environment
echo "System version: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Elixir version: $(elixir --version | head -1)"
echo "Node.js version: $(node --version)"
echo "Current directory: $(pwd)"

# TEMPORARY DEBUG: Log token information for validation
if [ "$MIX_ENV" = "prod" ]; then
  # Get first 8 chars of token safely with cut instead of parameter expansion
  FIRST_CHARS=""
  if [ -n "$WANDERER_PRODUCTION_BOT_TOKEN" ]; then
    FIRST_CHARS=$(echo "$WANDERER_PRODUCTION_BOT_TOKEN" | cut -c1-8)
    echo "TEMPORARY DEBUG: WANDERER_PRODUCTION_BOT_TOKEN first 8 chars: ${FIRST_CHARS}..."
  else
    echo "TEMPORARY DEBUG: WANDERER_PRODUCTION_BOT_TOKEN not set"
  fi

  echo "TEMPORARY DEBUG: Searching for baked-in token in release files..."
  # Try multiple locations where the token might be stored
  echo "In /app/releases:"
  grep -r "production_bot_token:" /app/releases 2>/dev/null || echo "Not found in /app/releases"

  echo "In /app/lib:"
  grep -r "production_bot_token:" /app/lib 2>/dev/null || echo "Not found in /app/lib"

  echo "In /app/config:"
  grep -r "production_bot_token:" /app/config 2>/dev/null || echo "Not found in /app/config"

  # Check sys.config which might have the token
  echo "In sys.config:"
  find /app -name "sys.config" -exec grep -l "token" {} \; -exec cat {} \; 2>/dev/null || echo "Not found in sys.config"
fi

# In production mode, we don't use environment variables for security
# The token should be baked into the release
if [ "$MIX_ENV" != "prod" ]; then
  # Only in development/test environments
  if [ -z "$BOT_API_TOKEN" ] && [ -n "$WANDERER_PRODUCTION_BOT_TOKEN" ]; then
    echo "Setting BOT_API_TOKEN from WANDERER_PRODUCTION_BOT_TOKEN (development only)"
    export BOT_API_TOKEN="$WANDERER_PRODUCTION_BOT_TOKEN"
  fi
else
  echo "Running in production mode - using baked-in configuration only"
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
