#!/bin/bash

# Test script for version tagging logic
# This script simulates what the GitHub workflow does

set -e

echo "🔍 Testing version tag creation logic..."

# Extract version from mix.exs (same as workflow)
VERSION=$(grep -E '^\s+version:' mix.exs | head -1 | grep -o '"[^"]*"' | tr -d '"')
echo "📋 Found version in mix.exs: $VERSION"

# Create tag names
TAG="v$VERSION"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
MAJOR_TAG="v$MAJOR"
MINOR_TAG="v$MAJOR.$MINOR"

echo "🏷️  Tags to be created:"
echo "   - Main tag: $TAG"
echo "   - Major tag: $MAJOR_TAG"
echo "   - Minor tag: $MINOR_TAG"

# Check if tags already exist
echo ""
echo "🔍 Checking existing tags..."

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ Tag $TAG already exists"
    EXISTS=true
else
    echo "✅ Tag $TAG does not exist"
    EXISTS=false
fi

if git rev-parse "$MAJOR_TAG" >/dev/null 2>&1; then
    echo "📋 Major tag $MAJOR_TAG exists (will be updated)"
else
    echo "📋 Major tag $MAJOR_TAG does not exist"
fi

if git rev-parse "$MINOR_TAG" >/dev/null 2>&1; then
    echo "📋 Minor tag $MINOR_TAG exists (will be updated)" 
else
    echo "📋 Minor tag $MINOR_TAG does not exist"
fi

echo ""
if [ "$EXISTS" = false ]; then
    echo "✅ Workflow would CREATE new tags"
    echo "🐳 Docker would build with tags:"
    echo "   - guarzo/wanderer-notifier:$VERSION"
    echo "   - guarzo/wanderer-notifier:$MAJOR.$MINOR"
    echo "   - guarzo/wanderer-notifier:$MAJOR"
    echo "   - guarzo/wanderer-notifier:latest"
    echo "   - guarzo/wanderer-notifier:main"
    echo "   - guarzo/wanderer-notifier:sha-$(git rev-parse --short HEAD)"
else
    echo "⏭️  Workflow would SKIP tag creation"
    echo "🐳 Docker build would be skipped on main branch"
fi

echo ""
echo "🎯 To trigger the workflow with new tags:"
echo "   1. Update version in mix.exs (currently: $VERSION)"
echo "   2. Commit and push to main branch"
echo "   3. Workflow will auto-create tags and build Docker images"

echo ""
echo "🔧 Current Docker Hub tags (what you mentioned seeing):"
echo "   - buildcache (build cache)"
echo "   - sha-xxxx (commit SHA)"
echo "   - latest (main branch)"
echo "   - main (main branch)"
echo ""
echo "❓ Missing semver tags suggests auto-tag job didn't run or failed"