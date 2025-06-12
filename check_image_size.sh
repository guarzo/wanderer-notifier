#!/usr/bin/env bash

# Script to check Docker image sizes

echo "=== Docker Image Size Comparison ==="
echo

# Check if original exists
if [ -f "Dockerfile.original" ]; then
    echo "Original Dockerfile (Debian-based):"
    docker build -f Dockerfile.original -t wanderer-notifier:debian . > /dev/null 2>&1
    docker images wanderer-notifier:debian --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
    echo
fi

echo "Alpine-based Dockerfile:"
docker build -f Dockerfile -t wanderer-notifier:alpine . > /dev/null 2>&1
docker images wanderer-notifier:alpine --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
echo

# Get the size in bytes for comparison
ALPINE_SIZE=$(docker images wanderer-notifier:alpine --format "{{.Size}}" | head -1)
echo "Alpine image size: $ALPINE_SIZE"

# Check if it's under 60MB
if [[ "$ALPINE_SIZE" =~ MB$ ]]; then
    SIZE_MB=$(echo "$ALPINE_SIZE" | sed 's/MB$//')
    if (( $(echo "$SIZE_MB < 60" | bc -l) )); then
        echo "✅ SUCCESS: Image is under 60MB!"
    else
        echo "❌ Image is $SIZE_MB MB, which is over the 60MB target"
    fi
fi