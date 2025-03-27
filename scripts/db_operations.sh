#!/bin/bash
# db_operations.sh - Database initialization and management operations for Wanderer Notifier
# This script provides commands for database initialization, migration, and backup

set -e

# Text formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage information
usage() {
  echo "Usage: $0 [COMMAND]"
  echo ""
  echo "Commands:"
  echo "  init      Create database if it doesn't exist and run migrations"
  echo "  migrate   Run migrations only"
  echo "  rollback  Rollback migrations to a specific version"
  echo "  backup    Create a database backup"
  echo "  verify    Check database connectivity and run a basic health check"
  echo ""
  echo "Environment variables:"
  echo "  WANDERER_DB_USER (or POSTGRES_USER)     - Database username"
  echo "  WANDERER_DB_PASSWORD (or POSTGRES_PASSWORD) - Database password"
  echo "  WANDERER_DB_HOST (or POSTGRES_HOST)     - Database hostname"
  echo "  WANDERER_DB_NAME (or POSTGRES_DB)       - Database name"
  echo "  WANDERER_DB_PORT (or POSTGRES_PORT)     - Database port"
  echo ""
  echo "Examples:"
  echo "  $0 init      # Initialize database"
  echo "  $0 backup    # Create a backup"
  exit 1
}

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

# Function to check database connectivity
check_db_connectivity() {
  log_message "info" "Checking database connectivity..."
  
  # Define a max retry count
  max_retries=10
  retry_count=0
  retry_delay=3
  connected=false
  
  # Try to connect to the database
  while [ $retry_count -lt $max_retries ] && [ "$connected" != "true" ]; do
    if pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER; then
      connected=true
      log_message "success" "Successfully connected to database"
    else
      retry_count=$((retry_count + 1))
      log_message "warning" "Failed to connect to database. Retrying in $retry_delay seconds ($retry_count/$max_retries)..."
      sleep $retry_delay
    fi
  done
  
  if [ "$connected" != "true" ]; then
    log_message "error" "Could not connect to database after $max_retries attempts"
    return 1
  fi
  
  return 0
}

# Function to initialize the database
initialize_db() {
  log_message "info" "Initializing database..."
  check_db_connectivity || return 1
  
  # Create the database using the Release module
  log_message "info" "Running createdb..."
  /app/bin/wanderer_notifier eval "WandererNotifier.Release.createdb()"
  
  # Run migrations
  log_message "info" "Running migrations..."
  /app/bin/wanderer_notifier eval "WandererNotifier.Release.migrate()"
  
  log_message "success" "Database initialization completed successfully"
  return 0
}

# Function to run migrations
run_migrations() {
  log_message "info" "Running migrations..."
  check_db_connectivity || return 1
  
  /app/bin/wanderer_notifier eval "WandererNotifier.Release.migrate()"
  
  log_message "success" "Migrations completed successfully"
  return 0
}

# Function to rollback migrations
rollback_migrations() {
  if [ -z "$1" ]; then
    log_message "error" "Version number required for rollback"
    return 1
  fi
  
  version=$1
  log_message "info" "Rolling back migrations to version $version..."
  check_db_connectivity || return 1
  
  /app/bin/wanderer_notifier eval "WandererNotifier.Release.rollback(WandererNotifier.Repo, $version)"
  
  log_message "success" "Rollback to version $version completed successfully"
  return 0
}

# Function to backup the database
backup_db() {
  log_message "info" "Creating database backup..."
  check_db_connectivity || return 1
  
  timestamp=$(date +%Y%m%d_%H%M%S)
  backup_file="/app/data/backups/db_backup_${timestamp}.sql"
  
  # Ensure backup directory exists
  mkdir -p /app/data/backups
  
  # Perform the backup using pg_dump
  PGPASSWORD=$POSTGRES_PASSWORD pg_dump -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB > $backup_file
  
  log_message "success" "Database backup created at $backup_file"
  return 0
}

# Function to verify database
verify_db() {
  log_message "info" "Verifying database..."
  check_db_connectivity || return 1
  
  # Check if tables exist
  table_count=$(PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
  
  log_message "info" "Found $table_count tables in database"
  
  log_message "success" "Database verification completed"
  return 0
}

# Main function
main() {
  # Check for command argument
  if [ $# -eq 0 ]; then
    usage
  fi
  
  # Get command
  command=$1
  
  # Map environment variables
  export POSTGRES_USER=${WANDERER_DB_USER:-${POSTGRES_USER:-postgres}}
  export POSTGRES_PASSWORD=${WANDERER_DB_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}
  export POSTGRES_HOST=${WANDERER_DB_HOST:-${POSTGRES_HOST:-postgres}}
  export POSTGRES_DB=${WANDERER_DB_NAME:-${POSTGRES_DB:-wanderer_notifier}}
  export POSTGRES_PORT=${WANDERER_DB_PORT:-${POSTGRES_PORT:-5432}}
  
  # Execute the appropriate function based on command
  case $command in
    "init")
      initialize_db
      ;;
    "migrate")
      run_migrations
      ;;
    "rollback")
      if [ -z "$2" ]; then
        log_message "error" "Version number required for rollback"
        exit 1
      fi
      rollback_migrations $2
      ;;
    "backup")
      backup_db
      ;;
    "verify")
      verify_db
      ;;
    *)
      log_message "error" "Unknown command: $command"
      usage
      ;;
  esac
}

# Run the main function with all arguments
main "$@" 