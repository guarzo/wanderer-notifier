#!/bin/bash

# Purpose: Start both the Elixir server and the JavaScript watcher for development
# This script helps ensure that JavaScript changes are immediately reflected in the Elixir app

# Define terminal colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting Wanderer Notifier Development Environment ===${NC}"

# Create necessary directories
echo -e "${YELLOW}Ensuring required directories exist...${NC}"
mkdir -p priv/static/app

# First, build the React app initially
echo -e "${YELLOW}Building React app...${NC}"
cd renderer && npm run build && cd ..

# Start the JS watcher in the background
echo -e "${YELLOW}Starting JavaScript file watcher...${NC}"
(cd renderer && npm run dev:sync) &
JS_WATCHER_PID=$!

# Trap Ctrl+C to kill all processes
trap 'kill $JS_WATCHER_PID 2>/dev/null' EXIT

# Start the Elixir server
echo -e "${GREEN}Starting Elixir server...${NC}"
echo -e "${YELLOW}(Press Ctrl+C to stop both servers)${NC}"
mix phx.server

# This will be executed when the script is interrupted
echo -e "${RED}Shutting down all processes...${NC}" 