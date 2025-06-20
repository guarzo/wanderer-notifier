#!/bin/bash

# Test script for validating Docker secrets implementation
set -e

echo "🔍 Testing Docker secrets implementation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEST_TOKEN="test_secret_token_12345"
IMAGE_NAME="wanderer-notifier-test"

cleanup() {
    echo "🧹 Cleaning up test artifacts..."
    docker rmi "$IMAGE_NAME:current" 2>/dev/null || true
    docker rmi "$IMAGE_NAME:secure" 2>/dev/null || true
    echo "secrets_test_token" | docker secret rm wanderer_secrets_test 2>/dev/null || true
}

trap cleanup EXIT

echo "📦 Building current implementation (with build-arg)..."
docker build -t "$IMAGE_NAME:current" \
    --build-arg NOTIFIER_API_TOKEN="$TEST_TOKEN" \
    --progress=plain \
    . 2>&1 | grep -E "(NOTIFIER_API_TOKEN|Step [0-9]+)" || true

echo -e "\n🔍 Checking if token is visible in current image history..."
if docker history --no-trunc "$IMAGE_NAME:current" | grep -q "$TEST_TOKEN"; then
    echo -e "${RED}❌ SECURITY ISSUE: Token found in image history!${NC}"
    docker history --no-trunc "$IMAGE_NAME:current" | grep "$TEST_TOKEN" || true
else
    echo -e "${GREEN}✅ Token not visible in basic history check${NC}"
fi

echo -e "\n🔍 Checking image layers for secrets..."
docker inspect "$IMAGE_NAME:current" | jq -r '.[] | .Config.Env[]?' | grep -i "NOTIFIER_API_TOKEN" || echo "No token found in environment"

echo -e "\n📊 Current image size:"
docker images "$IMAGE_NAME:current" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Test if we can extract the secret from the built image
echo -e "\n🕵️  Testing secret extraction from current image..."
EXTRACTED_TOKEN=$(docker run --rm "$IMAGE_NAME:current" /bin/sh -c 'echo $NOTIFIER_API_TOKEN' 2>/dev/null || echo "Failed to extract")
if [ "$EXTRACTED_TOKEN" = "$TEST_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  Token can be extracted from running container${NC}"
else
    echo -e "${GREEN}✅ Token not easily extractable${NC}"
fi

echo -e "\n${GREEN}✅ Current implementation test completed${NC}"
echo -e "\n📋 Recommendations:"
echo "1. Use BuildKit secrets: --secret id=notifier_token,src=token_file"
echo "2. Use multi-stage builds to avoid token in final image"
echo "3. Use runtime secrets injection instead of build-time"
echo "4. Consider using Docker Compose secrets for local development"

echo -e "\n🔧 Testing secure implementation:"
echo "Building with secure BuildKit secrets..."

# Test the secure implementation using the updated Dockerfile
echo "test_secure_token_67890" > /tmp/test_notifier_token

echo "📦 Building secure implementation..."
docker build --secret id=notifier_token,src=/tmp/test_notifier_token -t "$IMAGE_NAME:secure" \
    --progress=plain \
    . 2>&1 | grep -E "(Step [0-9]+|RUN --mount)" || true

echo -e "\n🔍 Checking if token is visible in secure image history..."
if docker history --no-trunc "$IMAGE_NAME:secure" | grep -q "test_secure_token_67890"; then
    echo -e "${RED}❌ SECURITY ISSUE: Token found in secure image history!${NC}"
else
    echo -e "${GREEN}✅ Token not visible in secure image history${NC}"
fi

echo -e "\n🔍 Checking secure image layers for secrets..."
docker inspect "$IMAGE_NAME:secure" | jq -r '.[] | .Config.Env[]?' | grep -i "NOTIFIER_API_TOKEN" || echo "✅ No token found in secure image environment"

echo -e "\n🏃 Testing secure image runtime (requires token via environment)..."
RUNTIME_TEST=$(docker run --rm -e NOTIFIER_API_TOKEN="runtime_token_test" "$IMAGE_NAME:secure" /bin/sh -c 'echo "Token accessible: $([[ -n "$NOTIFIER_API_TOKEN" ]] && echo "YES" || echo "NO")"' 2>/dev/null || echo "Failed to test runtime")
echo "Runtime result: $RUNTIME_TEST"

# Cleanup
rm -f /tmp/test_notifier_token

echo -e "\n${GREEN}✅ Secure implementation test completed${NC}"