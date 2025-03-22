#!/bin/bash
set -e

echo "Starting Wanderer Notifier..."
echo "Elixir version: $(elixir --version | head -n 1)"
echo "Node.js version: $(node --version)"

# In production, clear token environment variables to use baked-in values
if [ "$MIX_ENV" = "prod" ]; then
  unset NOTIFIER_API_TOKEN
fi

# Show configured ports
echo "Web server port: ${PORT:-4000}"
echo "Chart service port: ${CHART_SERVICE_PORT:-3001}"

# Set default cache directory if not specified
CACHE_DIR=${CACHE_DIR:-"/app/data/cache"}

# Ensure the cache directory exists with proper permissions
echo "Ensuring cache directory exists: $CACHE_DIR"
mkdir -p "$CACHE_DIR"
chmod -R 777 "$CACHE_DIR"

# Source any environment variables from .env file if it exists
if [ -f .env ]; then
  echo "Loading environment from .env file"
  set -a
  source .env
  set +a
fi

# Start the chart service
echo "Starting chart service on port ${CHART_SERVICE_PORT:-3001}..."
cd /app/chart-service && PORT=${CHART_SERVICE_PORT:-3001} npm start &
CHART_PID=$!
echo "Chart service started with PID: $CHART_PID"

# Start the main application
echo "Starting Elixir application on port ${PORT:-4000}..."
cd /app && exec /app/bin/wanderer_notifier start
