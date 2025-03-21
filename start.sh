#!/bin/sh
echo "=== Starting Wanderer Notifier ==="

# Check our environment
echo "System version: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Elixir version: $(elixir --version | head -1)"
echo "Node.js version: $(node --version)"
echo "Current directory: $(pwd)"

# Debug some key environment variables
echo "MIX_ENV: $MIX_ENV"
echo "PORT: $PORT"
echo "DISCORD_BOT_TOKEN set: ${DISCORD_BOT_TOKEN:+yes}"
echo "BOT_API_TOKEN set: ${BOT_API_TOKEN:+yes}"
echo "MAP_URL_WITH_NAME: ${MAP_URL_WITH_NAME:-(not set)}"

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
