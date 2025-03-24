#!/bin/bash
# Batch script to update multiple files with the new logger pattern

# Process API files
echo "=== Processing API files ==="
for file in $(find lib/wanderer_notifier/api -name "*.ex"); do
  echo "Updating $file with category 'api'"
  ./scripts/update_logger.sh "$file" "api"
  echo "---------------------------------"
done

# Process Cache files
echo "=== Processing Cache files ==="
for file in $(find lib/wanderer_notifier/cache -name "*.ex"); do
  echo "Updating $file with category 'cache'"
  ./scripts/update_logger.sh "$file" "cache"
  echo "---------------------------------"
done

# Process Resource files
echo "=== Processing Resource files ==="
for file in $(find lib/wanderer_notifier/resources -name "*.ex"); do
  echo "Updating $file with category 'persistence'"
  ./scripts/update_logger.sh "$file" "persistence"
  echo "---------------------------------"
done

# Process Scheduler files
echo "=== Processing Scheduler files ==="
for file in $(find lib/wanderer_notifier/schedulers -name "*.ex"); do
  echo "Updating $file with category 'scheduler'"
  ./scripts/update_logger.sh "$file" "scheduler"
  echo "---------------------------------"
done

# Process WebSocket files
echo "=== Processing WebSocket files ==="
for file in $(find lib/wanderer_notifier/websocket -name "*.ex"); do
  echo "Updating $file with category 'websocket'"
  ./scripts/update_logger.sh "$file" "websocket"
  echo "---------------------------------"
done

# Process Application and Core files
echo "=== Processing Application and Core files ==="
./scripts/update_logger.sh "lib/wanderer_notifier/application.ex" "startup"
for file in $(find lib/wanderer_notifier/core -name "*.ex"); do
  echo "Updating $file with category 'config'"
  ./scripts/update_logger.sh "$file" "config"
  echo "---------------------------------"
done

echo "=== Batch Update Complete ==="
echo "Now you need to:"
echo "1. Review each file to add structured metadata"
echo "2. Check for any remaining direct Logger calls"
echo "3. Test the updated logging"
echo "4. Run the find_logger_calls.sh script to verify progress" 