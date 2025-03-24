#!/bin/bash
# Script to help update log calls in files

if [ $# -lt 1 ]; then
  echo "Usage: $0 <file_path> [category]"
  echo "Example: $0 lib/wanderer_notifier/api/esi/client.ex api"
  echo ""
  echo "Available categories:"
  echo "  api - API interactions with external services"
  echo "  websocket - WebSocket connection and message handling"
  echo "  kill - Killmail processing"
  echo "  persistence - Database operations"
  echo "  processor - Message processing"
  echo "  cache - Cache operations"
  echo "  startup - Application startup events"
  echo "  config - Configuration loading"
  echo "  maintenance - Maintenance tasks"
  echo "  scheduler - Scheduled operations"
  exit 1
fi

FILE_PATH=$1
CATEGORY=${2:-"processor"}  # Default to processor if no category is specified

# Check if file exists
if [ ! -f "$FILE_PATH" ]; then
  echo "Error: File not found: $FILE_PATH"
  exit 1
fi

# Check if file already has the AppLogger alias
if grep -q "alias WandererNotifier.Logger, as: AppLogger" "$FILE_PATH"; then
  echo "✓ File already has AppLogger alias"
else
  echo "Adding AppLogger alias to file"
  # Use sed to add the alias after the 'require Logger' line
  sed -i '/require Logger/a alias WandererNotifier.Logger, as: AppLogger' "$FILE_PATH"
fi

# Count total Logger calls before changes
TOTAL_CALLS=$(grep -c "Logger\." "$FILE_PATH")
echo "Found $TOTAL_CALLS Logger calls to update"

# Create backup file
cp "$FILE_PATH" "${FILE_PATH}.bak"

# Replace common Logger patterns with AppLogger equivalents
echo "Applying replacements:"

# Replace Logger.info patterns
echo "  - Replacing Logger.info calls"
sed -i "s/Logger\.info(\(.*\))/AppLogger.${CATEGORY}_info(\1)/g" "$FILE_PATH"

# Replace Logger.debug patterns
echo "  - Replacing Logger.debug calls"
sed -i "s/Logger\.debug(\(.*\))/AppLogger.${CATEGORY}_debug(\1)/g" "$FILE_PATH"

# Replace Logger.warning patterns (note the inconsistency in Elixir's Logger module)
echo "  - Replacing Logger.warning calls"
sed -i "s/Logger\.warning(\(.*\))/AppLogger.${CATEGORY}_warn(\1)/g" "$FILE_PATH"

# Replace Logger.warn patterns
echo "  - Replacing Logger.warn calls"
sed -i "s/Logger\.warn(\(.*\))/AppLogger.${CATEGORY}_warn(\1)/g" "$FILE_PATH"

# Replace Logger.error patterns
echo "  - Replacing Logger.error calls"
sed -i "s/Logger\.error(\(.*\))/AppLogger.${CATEGORY}_error(\1)/g" "$FILE_PATH"

# Count remaining Logger calls
REMAINING_CALLS=$(grep -c "Logger\." "$FILE_PATH")
UPDATED_CALLS=$((TOTAL_CALLS - REMAINING_CALLS))

echo "Updated $UPDATED_CALLS calls. $REMAINING_CALLS calls remain."
echo "⚠️  Manual review required for remaining calls and to add structured metadata."
echo "A backup of the original file is saved at ${FILE_PATH}.bak"
echo ""
echo "Next steps:"
echo "1. Review the file and add structured metadata to log calls"
echo "2. Check for any remaining direct Logger calls"
echo "3. Follow the guidelines in docs/implementation-guides/logging-improvements.md" 