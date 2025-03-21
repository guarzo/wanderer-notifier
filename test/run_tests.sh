#!/usr/bin/env bash

# Stop on first error
set -e

# Set the MIX_ENV to test
export MIX_ENV=test

# Define colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Print header
echo -e "${YELLOW}=== Running Wanderer Notifier Tests ===${NC}"

# Create a function to run a specific test suite
run_test() {
  test_path=$1
  test_name=$2
  
  echo -e "\n${YELLOW}Running $test_name tests...${NC}"
  if mix test $test_path --trace; then
    echo -e "${GREEN}✓ $test_name tests passed!${NC}"
    return 0
  else
    echo -e "${RED}✗ $test_name tests failed!${NC}"
    return 1
  fi
}

# Compile the project first
echo -e "\n${YELLOW}Compiling project...${NC}"
mix compile

# Run specific test categories
run_test "test/wanderer_notifier/discord" "Discord Notifier"
run_test "test/wanderer_notifier/api/zkill" "ZKillboard API"
run_test "test/wanderer_notifier/api/map" "Map API"
run_test "test/wanderer_notifier/notifiers" "Formatter"

# Run all tests
echo -e "\n${YELLOW}Running all tests...${NC}"
if mix test --trace; then
  echo -e "\n${GREEN}All tests passed successfully!${NC}"
  exit 0
else
  echo -e "\n${RED}Some tests failed!${NC}"
  exit 1
fi 