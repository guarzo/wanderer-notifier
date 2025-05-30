#!/usr/bin/env bash
#
# listen_killmail.sh
#
# Continuously fetches from the RedisQ endpoint and extracts the 'package' field.

# --- Configuration ------------------------------------------
# Replace with your actual Queue ID:
QUEUE_ID="YourIdHere"
URL="https://zkillredisq.stream/listen.php?queueID=${QUEUE_ID}"

# How long to wait between polls (in seconds):
SLEEP_INTERVAL=1
# ------------------------------------------------------------

# Check for dependencies
command -v curl >/dev/null 2>&1 || { echo >&2 "Error: curl is not installed."; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo >&2 "Error: jq is not installed.";   exit 1; }

echo "Starting RedisQ listener for queueID=${QUEUE_ID} (poll every ${SLEEP_INTERVAL}s)..."

while true; do
  # Fetch raw JSON
  raw=$(curl -s "${URL}")
  if [[ -z "$raw" ]]; then
    echo "Warning: empty response, retrying in ${SLEEP_INTERVAL}s..."
    sleep "${SLEEP_INTERVAL}"
    continue
  fi

  # Parse out the 'package' field
  killmail=$(printf '%s' "$raw" | jq -r '.package // empty')
  if [[ -z "$killmail" ]]; then
    echo "No 'package' field found in response."
  else
    # Do something with the killmail JSON (or just print it)
    echo "$killmail"
  fi

  # Wait before next poll
  sleep "${SLEEP_INTERVAL}"
done

