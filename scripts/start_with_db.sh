#!/bin/bash
# start_with_db.sh - Start the application with proper database initialization
# This script ensures the database is ready before starting the application

set -e

# Text formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log output based on severity
log_message() {
  local severity=$1
  local message=$2
  
  case $severity in
    "error")
      echo -e "${RED}ERROR:${NC} $message"
      ;;
    "warning")
      echo -e "${YELLOW}WARNING:${NC} $message"
      ;;
    "info")
      echo -e "${BLUE}INFO:${NC} $message"
      ;;
    "success")
      echo -e "${GREEN}SUCCESS:${NC} $message"
      ;;
    *)
      echo -e "$message"
      ;;
  esac
}

# Check if database connectivity is required
db_required() {
  # If kill charts are enabled, database is required
  if [ "${WANDERER_FEATURE_KILL_CHARTS:-${ENABLE_KILL_CHARTS:-false}}" = "true" ]; then
    return 0
  fi
  
  return 1
}

# Wait for PostgreSQL to be ready
wait_for_postgres() {
  log_message "info" "Waiting for PostgreSQL to be ready..."
  
  local host="${WANDERER_DB_HOST:-${POSTGRES_HOST:-postgres}}"
  local port="${WANDERER_DB_PORT:-${POSTGRES_PORT:-5432}}"
  local user="${WANDERER_DB_USER:-${POSTGRES_USER:-postgres}}"
  
  # Define a max retry count
  local max_retries=30
  local retry_count=0
  local retry_delay=2
  local connected=false
  
  while [ $retry_count -lt $max_retries ] && [ "$connected" != "true" ]; do
    if pg_isready -h "$host" -p "$port" -U "$user"; then
      connected=true
      log_message "success" "Successfully connected to PostgreSQL"
    else
      retry_count=$((retry_count + 1))
      log_message "warning" "PostgreSQL is not ready. Retrying in $retry_delay seconds ($retry_count/$max_retries)..."
      sleep $retry_delay
    fi
  done
  
  if [ "$connected" != "true" ]; then
    log_message "error" "Could not connect to PostgreSQL after $max_retries attempts"
    return 1
  fi
  
  return 0
}

# Initialize the database
init_database() {
  log_message "info" "Initializing database..."
  
  # Create the database if it doesn't exist
  log_message "info" "Creating database if it doesn't exist..."
  /app/bin/wanderer_notifier eval "WandererNotifier.Release.createdb()"
  
  # Run migrations
  log_message "info" "Running database migrations..."
  /app/bin/wanderer_notifier eval "WandererNotifier.Release.migrate()"
  
  log_message "success" "Database initialization completed successfully"
}

# Validate environment variables
validate_env() {
  log_message "info" "Validating environment variables..."
  
  # Ensure critical variables are set
  local missing=false
  
  if [ -z "${WANDERER_DISCORD_BOT_TOKEN:-${DISCORD_BOT_TOKEN:-}}" ]; then
    log_message "error" "Discord bot token is required but not set"
    missing=true
  fi
  
  if [ -z "${WANDERER_DISCORD_CHANNEL_ID:-${DISCORD_CHANNEL_ID:-}}" ]; then
    log_message "error" "Discord channel ID is required but not set"
    missing=true
  fi
  
  if [ -z "${WANDERER_LICENSE_KEY:-${LICENSE_KEY:-}}" ]; then
    log_message "error" "License key is required but not set"
    missing=true
  fi
  
  if [ -z "${WANDERER_MAP_URL:-${MAP_URL_WITH_NAME:-}}" ]; then
    log_message "error" "Map URL is required but not set"
    missing=true
  fi
  
  if [ -z "${WANDERER_MAP_TOKEN:-${MAP_TOKEN:-}}" ]; then
    log_message "error" "Map token is required but not set"
    missing=true
  fi
  
  # Check if kill charts are enabled but database details are missing
  if [ "${WANDERER_FEATURE_KILL_CHARTS:-${ENABLE_KILL_CHARTS:-false}}" = "true" ]; then
    log_message "info" "Kill charts feature is enabled, validating database configuration..."
    
    if [ -z "${WANDERER_DB_HOST:-${POSTGRES_HOST:-}}" ]; then
      log_message "error" "Kill charts are enabled but database host is not set"
      missing=true
    fi
  fi
  
  if [ "$missing" = "true" ]; then
    log_message "error" "One or more required environment variables are missing"
    return 1
  fi
  
  log_message "success" "Environment validation completed"
  return 0
}

# Main function
main() {
  log_message "info" "Starting Wanderer Notifier..."
  
  # Validate environment variables
  validate_env || exit 1
  
  # Check if database is required
  if db_required; then
    log_message "info" "Database functionality is enabled, ensuring database is ready..."
    
    # Wait for PostgreSQL to be ready
    wait_for_postgres || exit 1
    
    # Initialize the database
    init_database || exit 1
  else
    log_message "info" "Database functionality is disabled, skipping database initialization"
  fi
  
  # Start the application
  log_message "info" "Starting the application..."
  exec /app/bin/wanderer_notifier start
}

# Run the main function
main 