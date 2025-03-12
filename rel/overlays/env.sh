#!/bin/sh

# Environment variables for WandererNotifier
# Discord configuration
export DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
export DISCORD_CHANNEL_ID="${DISCORD_CHANNEL_ID:-}"

# Map configuration
export MAP_URL="${MAP_URL:-}"
export MAP_NAME="${MAP_NAME:-}"
export MAP_TOKEN="${MAP_TOKEN:-}"
export MAP_URL_WITH_NAME="${MAP_URL_WITH_NAME:-}"

# Slack configuration
export SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# Application configuration
export PORT="${PORT:-4000}"
export HOST="${HOST:-0.0.0.0}"
export RELEASE_COOKIE="${RELEASE_COOKIE:-wanderer_notifier_cookie}"
export RELEASE_NODE="${RELEASE_NODE:-wanderer_notifier@127.0.0.1}"

# Set LANG if not already set
export LANG="${LANG:-en_US.UTF-8}"

# Set the environment
export MIX_ENV=prod

# Optional: Set the timezone
export TZ="${TZ:-UTC}" 