#!/bin/bash

# test_docker_image.sh - Validates a built Docker image for the Wanderer Notifier application
# This script performs basic validation to ensure the critical components are working

set -e

# Default values
IMAGE_NAME="guarzo/wanderer-notifier"
TAG="latest"
TIMEOUT=30

# Display help information
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Test and validate a Wanderer Notifier Docker image"
  echo
  echo "Options:"
  echo "  -i, --image IMAGE_NAME   Docker image name (default: $IMAGE_NAME)"
  echo "  -t, --tag TAG            Docker image tag (default: $TAG)"
  echo "  -h, --help               Display this help message"
  echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--image)
      IMAGE_NAME="$2"
      shift 2
      ;;
    -t|--tag)
      TAG="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

FULL_IMAGE="${IMAGE_NAME}:${TAG}"
echo "Testing image: $FULL_IMAGE"

# Function to run a command inside the container
run_in_container() {
  local cmd="$1"
  docker run --rm -t "$FULL_IMAGE" /bin/sh -c "$cmd"
}

# Check if the image exists
if ! docker image inspect "$FULL_IMAGE" &> /dev/null; then
  echo "Error: Image $FULL_IMAGE does not exist locally"
  exit 1
fi

echo "======= Basic System Tests ======="

echo "Checking OS and runtime versions..."
run_in_container "cat /etc/os-release && echo 'Elixir version:' && elixir --version"

echo "Checking GLIBC version..."
run_in_container "ldd --version | head -n1"

echo "Verifying file permissions..."
run_in_container "ls -la /app/bin/ && ls -la /app/data/"

echo "Checking data directories..."
run_in_container "find /app/data -type d | sort"

echo "======= Application Tests ======="

echo "Testing Elixir runtime..."
run_in_container "/app/bin/wanderer_notifier eval '1+1'"

echo "Checking application version..."
run_in_container "/app/bin/wanderer_notifier eval 'IO.puts Application.spec(:wanderer_notifier, :vsn)'"

echo "Verifying configuration loading..."
run_in_container "test -f /app/etc/wanderer_notifier.exs && echo 'Configuration file exists'"

echo "======= Connection Tests ======="

echo "Testing PostgreSQL client installation..."
run_in_container "psql --version"

echo "======= Script Tests ======="

echo "Checking database operations script..."
run_in_container "test -f /app/bin/db_operations.sh && echo 'Database operations script exists'"

echo "Checking startup script..."
run_in_container "test -f /app/bin/start_with_db.sh && echo 'Startup script exists'"

echo "======= Summary ======="
echo "✅ All basic validation tests completed for $FULL_IMAGE"
echo "Note: These are basic validation tests. For complete testing, additional integration tests should be run." 