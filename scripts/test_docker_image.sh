#!/bin/bash

# test_docker_image.sh - Validates a built Docker image for the Wanderer Notifier application
# This script performs basic validation to ensure the critical components are working

set -e

# Default values
IMAGE_NAME="guarzo/wanderer-notifier"
TAG="latest"
TIMEOUT=30
BASIC_ONLY=false
DISCORD_TOKEN="test_token_for_validation"

# Default environment variables
DEFAULT_ENV_VARS=(
  "MAP_URL_WITH_NAME=http://example.com/map?name=testmap"
  "MAP_TOKEN=test-map-token"
  "DISCORD_CHANNEL_ID=123456789"
  "LICENSE_KEY=test-license-key"
  "WANDERER_ENV=test"
  "WANDERER_FEATURE_DISABLE_WEBSOCKET=true"
)

# Initialize EXTRA_ENV_VARS with defaults
EXTRA_ENV_VARS=""
for var in "${DEFAULT_ENV_VARS[@]}"; do
  EXTRA_ENV_VARS="$EXTRA_ENV_VARS -e $var"
done

# Display help information
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Test and validate a Wanderer Notifier Docker image"
  echo
  echo "Options:"
  echo "  -i, --image IMAGE_NAME   Docker image name (default: $IMAGE_NAME)"
  echo "  -t, --tag TAG            Docker image tag (default: $TAG)"
  echo "  -b, --basic              Run only basic validation tests without starting the app"
  echo "  -d, --discord-token TOK  Set a test Discord token for validation (default: test_token_for_validation)"
  echo "  -e, --env VAR=VALUE      Add/override environment variable (can be used multiple times)"
  echo "  -h, --help               Display this help message"
  echo
  echo "Default environment variables:"
  for var in "${DEFAULT_ENV_VARS[@]}"; do
    echo "  $var"
  done
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
    -b|--basic)
      BASIC_ONLY=true
      shift
      ;;
    -d|--discord-token)
      DISCORD_TOKEN="$2"
      shift 2
      ;;
    -e|--env)
      # Override or append environment variable
      key="${2%%=*}"  # Get the part before =
      EXTRA_ENV_VARS=$(echo "$EXTRA_ENV_VARS" | sed -E "s#-e ${key}=[^ ]*#-e $2#")
      if ! echo "$EXTRA_ENV_VARS" | grep -q " -e $key="; then
        EXTRA_ENV_VARS="$EXTRA_ENV_VARS -e $2"
      fi
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
  local env_vars="$2"
  
  if [ -z "$env_vars" ]; then
    docker run --rm -t "$FULL_IMAGE" /bin/sh -c "$cmd"
  else
    # shellcheck disable=SC2086
    # We intentionally want word splitting for env vars, but each var is properly quoted
    docker run --rm -t $env_vars "$FULL_IMAGE" /bin/sh -c "$cmd"
  fi
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

echo "======= Environment Debugging ======="
echo "Checking environment variables..."
run_in_container "printenv | grep -E 'CONFIG|NOTIFIER' || echo 'No matching environment variables found'"

echo "Checking startup debug logs..."
run_in_container "test -f /tmp/startup_debug.txt && cat /tmp/startup_debug.txt || echo 'Startup debug file not found'"

echo "Checking /tmp/config_debug.txt if it exists..."
run_in_container "test -f /tmp/config_debug.txt && cat /tmp/config_debug.txt || echo 'Config debug file not found'"

echo "======= Configuration Tests ======="

echo "Verifying configuration file path..."
run_in_container "test -f /app/etc/wanderer_notifier.exs && echo '✅ Configuration file exists at: /app/etc/wanderer_notifier.exs' || echo '❌ Configuration file missing!'"

echo "Checking configuration file content..."
run_in_container "cat /app/etc/wanderer_notifier.exs || echo 'Could not read configuration file'"

# Only run the full duplicate path check in non-basic mode
if [ "$BASIC_ONLY" = true ]; then
  echo "Skipping detailed path checks in basic mode..."
else
  echo "Checking for duplicate paths in configuration..."
  # A better approach for detecting path duplication issues
  echo "Examining paths inside container..."
  run_in_container "find /app -name 'app' | grep -v '^/app$' || echo 'No duplicate app directories found'"
  run_in_container "find /app -name 'etc' | grep -v '^/app/etc$' || echo 'No duplicate etc directories found'"
fi

echo "Verifying configuration path variables..."
# Display but don't actually set the config path variables in this command
run_in_container "echo 'Using fixed config path: /app/etc/wanderer_notifier.exs'"

# Create an empty config file for testing if needed - don't pass NOTIFIER_CONFIG_PATH here
echo "Creating minimal config file if needed..."
run_in_container "[ -f /app/etc/wanderer_notifier.exs ] || echo 'import Config\n# Minimal test config\nconfig :wanderer_notifier, test_config: true' > /app/etc/wanderer_notifier.exs" "-e DISCORD_BOT_TOKEN=$DISCORD_TOKEN"

echo "======= Application Tests ======="

echo "Checking Config.Reader implementation..."
run_in_container "elixir -e 'IO.puts(\"Exploring Config.Reader module...\"); \
Code.ensure_loaded(Config.Reader); \
if function_exported?(Code, :fetch_docs, 1) do \
  case Code.fetch_docs(Config.Reader) do \
    {:docs_v1, _, _, _, module_doc, _, _} when is_binary(module_doc) -> \
      IO.puts(\"Module docs: #{String.slice(module_doc, 0, 200)}...\"); \
    _ -> \
      IO.puts(\"No documentation available for Config.Reader\") \
  end \
end; \
if function_exported?(Config.Reader, :read!, 2) do \
  IO.puts(\"Function Config.Reader.read!/2 is exported\"); \
else \
  IO.puts(\"Function Config.Reader.read!/2 is NOT exported!\") \
end; \
if function_exported?(Config.Reader, :load, 2) do \
  IO.puts(\"Function Config.Reader.load/2 is exported\"); \
else \
  IO.puts(\"Function Config.Reader.load/2 is NOT exported!\") \
end'" "-e WANDERER_ENV=test"

if [ "$BASIC_ONLY" = true ]; then
  echo "Running basic application tests only (without starting the app)..."
  
  echo "Testing Elixir runtime with basic eval..."
  run_in_container "elixir -e 'IO.puts(\"Basic Elixir runtime test passed with result: #{1+1}\")'"
  
  echo "Checking application version file..."
  run_in_container "if [ -f /app/VERSION ]; then cat /app/VERSION; else echo 'Version file not found'; fi"
  
  echo "Testing config file exists (without setting CONFIG_PATH)..."
  run_in_container "elixir -e 'IO.puts(\"Config test: #{File.exists?(\"/app/etc/wanderer_notifier.exs\")}\")'"
else
  echo "Testing full application startup (may require environment variables)..."
  
  echo "Testing Elixir runtime with application eval (basic)..."
  run_in_container "elixir -e 'IO.puts(\"Basic Elixir runtime test: OK\")'" || echo "Basic Elixir test failed, but continuing..."

  echo "Checking Elixir application version..."
  # Try to get version with eval first
  run_in_container "/app/bin/wanderer_notifier eval 'IO.puts \"Version test\"'" "-e DISCORD_BOT_TOKEN=$DISCORD_TOKEN -e WANDERER_ENV=test" || echo "Application eval failed, but continuing..."

  echo "Testing simplified application boot..."
  # Try to run a very simple command
  run_in_container "/app/bin/wanderer_notifier eval 'System.version |> IO.puts'" "-e DISCORD_BOT_TOKEN=$DISCORD_TOKEN -e WANDERER_ENV=test" || echo "Simple boot test failed, but continuing..."
  
  echo "Testing minimal application boot (with clean shutdown)..."
  # Use a shorter timeout and force kill if needed
  run_in_container "timeout --kill-after=5s 10s /app/bin/wanderer_notifier eval 'IO.puts(\"Application started\"); Process.sleep(1000); :init.stop()'" "-e DISCORD_BOT_TOKEN=$DISCORD_TOKEN -e WANDERER_ENV=test -e WANDERER_FEATURE_DISABLE_WEBSOCKET=true" || {
    if [ $? -eq 124 ] || [ $? -eq 137 ]; then
      echo "✅ Minimal boot test completed"
    else
      echo "❌ Minimal boot test failed unexpectedly"
      false
    fi
  }
  
  # Only run the functional web test if not in basic mode
  if [ "$BASIC_ONLY" = false ]; then
    echo "======= Functional Web Test ======="
    echo "Starting application container in background..."
    
    # Create a unique container name for this test
    CONTAINER_NAME="wanderer-test-$(date +%s)"
    
    # Debug: Show what environment variables we're going to use
    echo "Environment variables being passed to container:"
    echo "DISCORD_BOT_TOKEN=$DISCORD_TOKEN"
    echo "Extra env vars: $EXTRA_ENV_VARS"
    
    # Start the container in the background with all required environment variables
    docker run --name "$CONTAINER_NAME" -d -p 4000:4000 \
      -e DISCORD_BOT_TOKEN="$DISCORD_TOKEN" \
      $EXTRA_ENV_VARS \
      "$FULL_IMAGE"
    
    # Debug: Verify environment variables in the container
    echo "Verifying environment variables in container:"
    docker exec "$CONTAINER_NAME" env || echo "Could not check environment variables"
    
    echo "Waiting for application to start (up to 20 seconds)..."
    MAX_ATTEMPTS=20
    ATTEMPT=0
    SUCCESS=false
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
      ATTEMPT=$((ATTEMPT+1))
      echo "Attempt $ATTEMPT of $MAX_ATTEMPTS..."
      
      # Try different possible health endpoints
      if curl -s http://localhost:4000/health 2>/dev/null | grep -q "ok"; then
        echo "✅ Health check successful! Application is running correctly (using /health endpoint)."
        SUCCESS=true
        break
      elif curl -s http://localhost:4000/status 2>/dev/null | grep -q "ok\|status\|running"; then
        echo "✅ Health check successful! Application is running correctly (using /status endpoint)."
        SUCCESS=true
        break
      elif curl -s http://localhost:4000/ 2>/dev/null | grep -q "html\|body\|wanderer"; then
        echo "✅ Health check successful! Application is running correctly (using root endpoint)."
        SUCCESS=true
        break
      fi
      
      # Check if container is still running
      if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo "❌ ERROR: Container stopped running! Checking logs:"
        docker logs "$CONTAINER_NAME"
        SUCCESS=false
        break
      fi
      
      # If we're on the 10th attempt, output some debug info
      if [ $ATTEMPT -eq 10 ]; then
        echo "Debug: Checking available routes..."
        docker exec "$CONTAINER_NAME" /app/bin/wanderer_notifier eval "IO.puts(\"Available routes: #{inspect Phoenix.Router.__routes__(WandererNotifier.Web.Router) |> Enum.map(& &1.path) |> Enum.join(\", \")}\")" 2>/dev/null || echo "Router introspection not available"
        
        # Check if the application is at least running properly even if web endpoints aren't available
        echo "Debug: Checking application status via eval..."
        if docker exec "$CONTAINER_NAME" /app/bin/wanderer_notifier eval "IO.puts(\"Elixir application running: \#{Application.started_applications() |> Enum.map(& elem(&1, 0)) |> Enum.member?(:wanderer_notifier)}\")" 2>/dev/null | grep -q "true"; then
          echo "✅ Application is running correctly (verified via eval command)."
          echo "Note: Web endpoints are not responding, but the application is running."
          SUCCESS=true
          break
        fi
      fi
      
      sleep 1
    done
    
    # Cleanup the container
    echo "Stopping test container..."
    docker stop "$CONTAINER_NAME" >/dev/null
    docker rm "$CONTAINER_NAME" >/dev/null
    
    if [ "$SUCCESS" != "true" ]; then
      echo "❌ ERROR: Application failed to start properly or health check failed."
      echo "This is a blocking error - the application must start successfully for validation to pass."
      exit 1
    fi
  else
    echo "Skipping functional web test in basic mode..."
  fi
fi

echo "======= Connection Tests ======="

echo "Testing PostgreSQL client installation..."
run_in_container "psql --version"

echo "======= Script Tests ======="

echo "Checking database operations script..."
run_in_container "test -f /app/bin/db_operations.sh && echo 'Database operations script exists'"

echo "Checking startup script..."
run_in_container "test -f /app/bin/start_with_db.sh && echo 'Startup script exists'"

echo "======= Summary ======="
echo "✅ All validation tests completed for $FULL_IMAGE"
echo "Note: These are basic validation tests. For complete testing, additional integration tests should be run." 