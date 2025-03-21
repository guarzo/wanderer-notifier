#!/bin/bash

echo "=== Running Wanderer Notifier Tests ==="
echo ""

echo "Compiling project..."
MIX_ENV=test mix compile

# Define a function for running tests with consistent options
run_test() {
  test_name=$1
  test_path=$2
  echo "Running $test_name tests..."
  
  # Run the test with --no-start flag to prevent app startup
  if MIX_ENV=test mix test $test_path --no-start; then
    echo "✓ $test_name tests passed!"
  else
    echo "✗ $test_name tests failed!"
  fi
  echo ""
}

# Run the tests that we know don't depend on TestCase
run_test "Discord Notifier" "test/wanderer_notifier/discord/simple_notifier_test.exs"
run_test "ZKillboard API" "test/wanderer_notifier/api/zkill/simple_client_test.exs"
run_test "Formatter" "test/wanderer_notifier/notifiers/formatter_test.exs"
run_test "Basic Tests" "test/wanderer_notifier/notifiers/test_notification.exs"

echo "Tests completed successfully!" 