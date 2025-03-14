#!/bin/bash
set -e

echo "Ensuring priv/templates directory exists..."
mkdir -p priv/templates

echo "Copying templates from lib to priv..."
cp -f lib/wanderer_notifier/web/templates/*.eex priv/templates/

echo "Building release..."
MIX_ENV=prod mix release

echo "Build completed successfully!" 