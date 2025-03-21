#!/bin/sh
echo "=== Starting Wanderer Notifier ==="

# Check our environment
echo "System version: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Elixir version: $(elixir --version | head -1)"
echo "Node.js version: $(node --version)"
echo "Locale: $(locale | grep LANG)"
echo "Current directory: $(pwd)"

# Debug environment variables
echo "Environment variables:"
echo "MIX_ENV: $MIX_ENV"
echo "PORT: $PORT"
echo "HOST: $HOST"

echo "Starting chart service..."
echo "Starting chart service on port $CHART_SERVICE_PORT"
cd /app/chart-service && node chart-generator.js &
CHART_PID=$!
echo "Chart service started with PID: $CHART_PID"

echo "Starting Elixir application..."
cd /app

# Verify the release directory structure
find /app/releases -type d | sort

# Check if the release script exists
if [ -x "/app/bin/wanderer_notifier" ]; then
  echo "Using release script"
  # Override RELEASE_DISTRIBUTION to prevent Erlang distribution issues
  RELEASE_DISTRIBUTION=none RELEASE_NODE=none bin/wanderer_notifier start
else
  echo "Error: Release script not found or not executable"
  echo "Files in bin directory:"
  ls -la /app/bin/ || echo "No bin directory"
  exit 1
fi
