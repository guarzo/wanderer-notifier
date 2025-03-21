#!/bin/sh

# Environment variables for Wanderer Notifier
# Required environment variables
export DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
export DISCORD_CHANNEL_ID="${DISCORD_CHANNEL_ID:-}"
export LICENSE_KEY="${LICENSE_KEY:-}"

# Map configuration
export MAP_URL="${MAP_URL:-}"
export MAP_TOKEN="${MAP_TOKEN:-}"
export MAP_URL_WITH_NAME="${MAP_URL_WITH_NAME:-}"

# Application configuration
export PORT="${PORT:-4000}"
export HOST="${HOST:-0.0.0.0}"
export MIX_ENV=prod
export LANG="${LANG:-en_US.UTF-8}"
export TZ="${TZ:-UTC}"

# In production mode, clear token environment variable to use baked-in value
if [ "${MIX_ENV}" = "prod" ]; then
  unset NOTIFIER_API_TOKEN
fi 