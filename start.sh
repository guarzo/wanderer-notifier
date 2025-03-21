#!/bin/bash
set -e

echo "Starting Wanderer Notifier..."
echo "Elixir version: $(elixir --version | head -n 1)"
echo "Node.js version: $(node --version)"

# In production, clear token environment variables to use baked-in values
if [ "$MIX_ENV" = "prod" ]; then
  unset NOTIFIER_API_TOKEN
fi

# Start the chart service
echo "Starting chart service..."
cd /app/chart-service && npm start &
CHART_PID=$!
echo "Chart service started with PID: $CHART_PID"

# Start the main application
echo "Starting Elixir application..."
cd /app && exec /app/bin/wanderer_notifier start
