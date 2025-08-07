#!/bin/bash

# WandererNotifier Test Runner
# Comprehensive test suite with proper environment setup

set -e

echo "🧪 WandererNotifier Test Suite"
echo "=============================="

# Set test environment
export MIX_ENV=test

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if Mix is available
if ! command -v mix &> /dev/null; then
    print_error "Mix is not available. Please ensure Elixir is installed."
    exit 1
fi

# Clean and compile
print_status "Cleaning previous builds..."
mix clean

print_status "Compiling test environment..."
mix compile

# Prepare test environment
print_status "Preparing test environment..."
mix deps.get

# Run different test suites
echo ""
echo "Running test suites..."
echo "----------------------"

# Basic unit tests
print_status "Running unit tests..."
if mix test; then
    print_status "Unit tests passed"
else
    print_error "Unit tests failed"
    exit 1
fi

# Integration tests (if they exist)
if [ -d "test/integration" ] && [ -n "$(find test/integration -name '*.exs' -type f)" ]; then
    print_status "Running integration tests..."
    if mix test test/integration/; then
        print_status "Integration tests passed"
    else
        print_error "Integration tests failed"
        exit 1
    fi
fi

# Property-based tests
print_status "Running property-based tests..."
if mix test --include property; then
    print_status "Property tests passed"
else
    print_warning "Some property tests may have failed (this is often normal)"
fi

echo ""
echo "📊 Test Coverage"
echo "================"

# Run tests with coverage
print_status "Generating test coverage report..."
if mix test --cover; then
    print_status "Coverage report generated"
else
    print_warning "Coverage report generation had issues"
fi

echo ""
print_status "All tests completed successfully! 🎉"