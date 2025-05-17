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
  -d TOKEN   Set WANDERER_DISCORD_BOT_TOKEN for tests
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
WANDERER_ENV=test
WANDERER_DISCORD_BOT_TOKEN=${TEST_TOKEN:-test_token}
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
COMMANDS=(
  "elixir --version"
  "ldd --version | head -n1"
  "mix help"
)

if [ "$BASIC_ONLY" = false ]; then
  COMMANDS+=("wget --spider http://localhost:4000/health")
fi

for cmd in "${COMMANDS[@]}"; do
  echo "→ Running: $cmd"
  docker exec "$CONTAINER_ID" sh -c "$cmd"
done

echo "All tests succeeded. Cleaning up."
docker rm -f "$CONTAINER_ID" > /dev/null
