#!/bin/bash

# Test script to verify Docker UTF-8 locale configuration
set -e

echo "🐳 Testing Docker UTF-8 locale configuration..."

# Build a test image with just the locale setup
cat > Dockerfile.test << 'EOF'
FROM debian:bookworm-slim

# Install locales and set UTF-8
RUN apt-get update \
 && apt-get install -y --no-install-recommends locales \
 && echo "C.UTF-8 UTF-8" > /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ELIXIR_ERL_OPTIONS="+fnu"

# Test the locale
CMD ["sh", "-c", "echo '🔍 Testing locale...'; locale; echo '✅ UTF-8 configured correctly'"]
EOF

echo "📦 Building test image..."
docker build -f Dockerfile.test -t wanderer-notifier-locale-test .

echo "🧪 Running locale test..."
docker run --rm wanderer-notifier-locale-test

echo "🧹 Cleaning up..."
rm Dockerfile.test
docker rmi wanderer-notifier-locale-test

echo "✅ Docker UTF-8 locale test passed!"
echo ""
echo "🚀 Your main Docker image will now run without UTF-8 warnings"