#!/usr/bin/env bash
set -euo pipefail

IMAGE="guarzo/wanderer-notifier"
TAG="latest"
BASIC_ONLY=false
TEST_TOKEN=""
declare -a EXTRA_ENVS

usage() {
  cat <<EOF
Usage: $0 [-i image] [-t tag] [-b] [-d token] [-e VAR=VAL] [-h]

  -i IMAGE   Docker image name (default: $IMAGE)
  -t TAG     Docker image tag (default: $TAG)
  -b         Run only basic checks (skip HTTP endpoint test)
  -d TOKEN   Set DISCORD_BOT_TOKEN for tests
  -e VAR=VAL Add extra environment variable (can be specified multiple times)
  -h         Show this help message
EOF
}

while getopts ":i:t:bd:e:h" opt; do
  case $opt in
    i) IMAGE="$OPTARG" ;;
    t) TAG="$OPTARG" ;;
    b) BASIC_ONLY=true ;;
    d) TEST_TOKEN="$OPTARG" ;;
    e) EXTRA_ENVS+=("$OPTARG") ;;
    h) usage; exit 0 ;;
    *) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

FULL_IMAGE="$IMAGE:$TAG"
CONTAINER_NAME="test_container_$$"

# Build a temporary env-file
ENV_FILE=$(mktemp)
trap 'rm -f "$ENV_FILE"' EXIT

# Base test env
cat > "$ENV_FILE" <<EOF
ENV=test
DISCORD_BOT_TOKEN=${TEST_TOKEN:-test_token}
LICENSE_KEY=test_license
MAP_URL=http://test.example.com
MAP_NAME=test-map
MAP_API_KEY=test_api_key
DISCORD_CHANNEL_ID=123456789
EOF

# Append any extras
for ev in "${EXTRA_ENVS[@]}"; do
  echo "$ev" >> "$ENV_FILE"
done

echo "Launching container $CONTAINER_NAME from $FULL_IMAGE..."
# Capture the container ID on the first (and only) run
CONTAINER_ID=$(docker run -d --name "$CONTAINER_NAME" --env-file "$ENV_FILE" -p 4000:4000 "$FULL_IMAGE")

# Give it a moment to start (or crash)
sleep 1

# Check if it stayed up
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_ID")" != "true" ]; then
  echo "Container failed to start. Logs:"
  docker logs "$CONTAINER_ID" || true
  docker rm "$CONTAINER_ID" > /dev/null || true
  exit 1
fi

echo "Container is running as $CONTAINER_ID."

echo "Waiting for health endpoint…"
until docker exec "$CONTAINER_ID" wget -q -O- http://localhost:4000/health; do
  echo "  still waiting..."
  sleep 2
done
echo "Health check passed."

# Define commands to validate
RUNTIME_COMMANDS=(
  "ls -la /app/bin"
  "ls -la /app/lib"
  "/app/bin/wanderer_notifier version"
  "ps aux | grep wanderer_notifier"
)

BASIC_COMMANDS=(
  "whoami"
  "uname -a"
  "which wget"
)

if [ "$BASIC_ONLY" = false ]; then
  RUNTIME_COMMANDS+=("wget --spider http://localhost:4000/health")
fi

echo "→ Running basic system checks..."
for cmd in "${BASIC_COMMANDS[@]}"; do
  echo "  → Running: $cmd"
  docker exec "$CONTAINER_ID" sh -c "$cmd" || echo "    (command failed, but continuing...)"
done

echo "→ Running runtime application checks..."
for cmd in "${RUNTIME_COMMANDS[@]}"; do
  echo "  → Running: $cmd"
  docker exec "$CONTAINER_ID" sh -c "$cmd"
done

echo "All tests succeeded. Cleaning up."
docker rm -f "$CONTAINER_ID" > /dev/null
