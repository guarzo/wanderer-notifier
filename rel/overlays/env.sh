#!/bin/sh

# Environment variables for Wanderer Notifier
# This script supports both the legacy and new naming conventions

# Core Discord configuration
export DISCORD_BOT_TOKEN="${WANDERER_DISCORD_BOT_TOKEN:-${DISCORD_BOT_TOKEN:-}}"
export WANDERER_DISCORD_BOT_TOKEN="${WANDERER_DISCORD_BOT_TOKEN:-${DISCORD_BOT_TOKEN:-}}"
export DISCORD_CHANNEL_ID="${WANDERER_DISCORD_CHANNEL_ID:-${DISCORD_CHANNEL_ID:-}}"
export WANDERER_DISCORD_CHANNEL_ID="${WANDERER_DISCORD_CHANNEL_ID:-${DISCORD_CHANNEL_ID:-}}"

# License configuration
export LICENSE_KEY="${WANDERER_LICENSE_KEY:-${LICENSE_KEY:-}}"
export WANDERER_LICENSE_KEY="${WANDERER_LICENSE_KEY:-${LICENSE_KEY:-}}"

# License manager URL configuration
export LICENSE_MANAGER_URL="${WANDERER_LICENSE_MANAGER_URL:-${LICENSE_MANAGER_URL:-https://lm.wanderer.ltd}}"
export WANDERER_LICENSE_MANAGER_URL="${WANDERER_LICENSE_MANAGER_URL:-${LICENSE_MANAGER_URL:-https://lm.wanderer.ltd}}"

# Map configuration
export MAP_URL="${WANDERER_MAP_URL:-${MAP_URL:-}}"
export WANDERER_MAP_URL="${WANDERER_MAP_URL:-${MAP_URL:-}}"
export MAP_TOKEN="${WANDERER_MAP_TOKEN:-${MAP_TOKEN:-}}"
export WANDERER_MAP_TOKEN="${WANDERER_MAP_TOKEN:-${MAP_TOKEN:-}}"
export MAP_URL_WITH_NAME="${WANDERER_MAP_URL:-${MAP_URL_WITH_NAME:-}}"
export WANDERER_MAP_URL="${WANDERER_MAP_URL:-${MAP_URL_WITH_NAME:-}}"

# Web server configuration
export PORT="${WANDERER_PORT:-${PORT:-4000}}"
export WANDERER_PORT="${WANDERER_PORT:-${PORT:-4000}}"
export HOST="${WANDERER_HOST:-${HOST:-0.0.0.0}}"
export WANDERER_HOST="${WANDERER_HOST:-${HOST:-0.0.0.0}}"
export SCHEME="${WANDERER_SCHEME:-${SCHEME:-http}}"
export WANDERER_SCHEME="${WANDERER_SCHEME:-${SCHEME:-http}}"

# Database configuration
export POSTGRES_USER="${WANDERER_DB_USER:-${POSTGRES_USER:-postgres}}"
export WANDERER_DB_USER="${WANDERER_DB_USER:-${POSTGRES_USER:-postgres}}"
export POSTGRES_PASSWORD="${WANDERER_DB_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}"
export WANDERER_DB_PASSWORD="${WANDERER_DB_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}"
export POSTGRES_HOST="${WANDERER_DB_HOST:-${POSTGRES_HOST:-postgres}}"
export WANDERER_DB_HOST="${WANDERER_DB_HOST:-${POSTGRES_HOST:-postgres}}"
export POSTGRES_DB="${WANDERER_DB_NAME:-${POSTGRES_DB:-wanderer_notifier}}"
export WANDERER_DB_NAME="${WANDERER_DB_NAME:-${POSTGRES_DB:-wanderer_notifier}}"
export POSTGRES_PORT="${WANDERER_DB_PORT:-${POSTGRES_PORT:-5432}}"
export WANDERER_DB_PORT="${WANDERER_DB_PORT:-${POSTGRES_PORT:-5432}}"

# Feature flags
export ENABLE_KILL_CHARTS="${WANDERER_FEATURE_KILL_CHARTS:-${ENABLE_KILL_CHARTS:-false}}"
export WANDERER_FEATURE_KILL_CHARTS="${WANDERER_FEATURE_KILL_CHARTS:-${ENABLE_KILL_CHARTS:-false}}"
export ENABLE_MAP_CHARTS="${WANDERER_FEATURE_MAP_CHARTS:-${ENABLE_MAP_CHARTS:-false}}"
export WANDERER_FEATURE_MAP_CHARTS="${WANDERER_FEATURE_MAP_CHARTS:-${ENABLE_MAP_CHARTS:-false}}"
export ENABLE_TRACK_KSPACE_SYSTEMS="${WANDERER_FEATURE_TRACK_KSPACE:-${ENABLE_TRACK_KSPACE_SYSTEMS:-true}}"
export WANDERER_FEATURE_TRACK_KSPACE="${WANDERER_FEATURE_TRACK_KSPACE:-${ENABLE_TRACK_KSPACE_SYSTEMS:-true}}"

# Cache configuration
export CACHE_DIR="${WANDERER_CACHE_DIR:-${CACHE_DIR:-/app/data/cache}}"
export WANDERER_CACHE_DIR="${WANDERER_CACHE_DIR:-${CACHE_DIR:-/app/data/cache}}"

# Application configuration
export MIX_ENV=prod
export LANG="${LANG:-en_US.UTF-8}"
export TZ="${TZ:-UTC}"
export CONFIG_PATH="/app/etc"

# API token handling
if [ "${MIX_ENV}" = "prod" ]; then
  # In production mode
  if [ -n "${WANDERER_NOTIFIER_API_TOKEN}" ] || [ -n "${NOTIFIER_API_TOKEN}" ]; then
    # If environment variables are set, use them (security override)
    export NOTIFIER_API_TOKEN="${WANDERER_NOTIFIER_API_TOKEN:-${NOTIFIER_API_TOKEN}}"
    export WANDERER_NOTIFIER_API_TOKEN="${WANDERER_NOTIFIER_API_TOKEN:-${NOTIFIER_API_TOKEN}}"
    echo "Using API token from environment variable"
  else
    # Otherwise, clear token environment variables to use baked-in value
    echo "Using baked-in API token from release configuration"
    unset NOTIFIER_API_TOKEN
    unset WANDERER_NOTIFIER_API_TOKEN
  fi
else
  # In development mode, ensure both variables are set for compatibility
  export NOTIFIER_API_TOKEN="${WANDERER_NOTIFIER_API_TOKEN:-${NOTIFIER_API_TOKEN:-}}"
  export WANDERER_NOTIFIER_API_TOKEN="${WANDERER_NOTIFIER_API_TOKEN:-${NOTIFIER_API_TOKEN:-}}"
fi 