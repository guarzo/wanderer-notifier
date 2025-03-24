#!/bin/bash
# Script to find direct Logger calls that need to be updated to use the new AppLogger

echo "Finding direct Logger calls to update..."

# Initialize counters
TOTAL_FILES=0
UPDATED_FILES=0
NEEDS_UPDATE_FILES=0

# Find all Elixir files
for FILE in $(find lib -name "*.ex"); do
  ((TOTAL_FILES++))
  
  # Check if file uses AppLogger already
  if grep -q "alias WandererNotifier.Logger, as: AppLogger" "$FILE"; then
    # Already migrated
    ((UPDATED_FILES++))
    continue
  fi
  
  # Check if file directly uses Logger
  if grep -q "Logger\." "$FILE"; then
    echo "File needs update: $FILE"
    # Count direct Logger calls
    CALLS=$(grep -c "Logger\." "$FILE")
    echo "  - Contains $CALLS direct Logger calls"
    ((NEEDS_UPDATE_FILES++))
  fi
done

echo "---------------------------------"
echo "Summary:"
echo "  Total Elixir files:           $TOTAL_FILES"
echo "  Already using AppLogger:      $UPDATED_FILES"
echo "  Files needing migration:      $NEEDS_UPDATE_FILES"
echo "---------------------------------"

# Show instructions for next steps
echo "To update a file with our new logger pattern:"
echo "1. Add 'alias WandererNotifier.Logger, as: AppLogger' to the top of the file"
echo "2. Replace 'Logger.info(\"message\")' with 'AppLogger.category_info(\"message\", metadata_key: value)'"
echo "3. Follow the guidelines in docs/implementation-guides/logging-improvements.md"
echo "" 