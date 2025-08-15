#!/bin/bash

# Diagnostic script for Discord configuration issues
# Run with: bash debug_discord_config.sh

echo ""
echo "=== Discord Configuration Diagnostic ==="
echo ""

# Check environment variable directly
echo "1. Environment variable DISCORD_APPLICATION_ID:"
if [ -z "$DISCORD_APPLICATION_ID" ]; then
    echo "   NOT SET or EMPTY"
else
    echo "   Raw value: '$DISCORD_APPLICATION_ID'"
    echo "   Length: ${#DISCORD_APPLICATION_ID}"
    
    # Show hex dump to reveal hidden characters
    echo "   Hex dump:"
    echo -n "   "
    echo -n "$DISCORD_APPLICATION_ID" | xxd -p | fold -w 60 | sed 's/^/   /'
    
    # Check for whitespace
    trimmed=$(echo "$DISCORD_APPLICATION_ID" | xargs)
    if [ "$DISCORD_APPLICATION_ID" != "$trimmed" ]; then
        echo "   ⚠️  WARNING: Contains leading/trailing whitespace"
        echo "   Trimmed value: '$trimmed'"
    fi
fi

echo ""
echo "2. Character analysis:"
if [ ! -z "$DISCORD_APPLICATION_ID" ]; then
    # Check for quotes
    if [[ "$DISCORD_APPLICATION_ID" == \"* ]] || [[ "$DISCORD_APPLICATION_ID" == *\" ]]; then
        echo "   ⚠️  WARNING: Value contains quotes - should be unquoted"
    fi
    
    # Check if numeric
    if [[ "$DISCORD_APPLICATION_ID" =~ ^[0-9]+$ ]]; then
        echo "   ✓ Value contains only digits"
    else
        echo "   ⚠️  WARNING: Value contains non-digit characters"
        # Show which characters are non-digits
        echo -n "   Non-digit characters: "
        echo "$DISCORD_APPLICATION_ID" | grep -o '[^0-9]' | sort -u | tr '\n' ' '
        echo ""
    fi
    
    # Check length (Discord app IDs are typically 18-19 digits)
    length=${#DISCORD_APPLICATION_ID}
    if [ $length -lt 17 ] || [ $length -gt 20 ]; then
        echo "   ⚠️  WARNING: Unusual length for Discord app ID (expected 18-19 digits, got $length)"
    fi
fi

echo ""
echo "3. All Discord environment variables:"
for var in DISCORD_APPLICATION_ID DISCORD_BOT_TOKEN DISCORD_CHANNEL_ID DISCORD_GUILD_ID; do
    value="${!var}"
    if [ -z "$value" ]; then
        echo "   $var: NOT SET"
    else
        echo "   $var: SET (length: ${#value})"
    fi
done

echo ""
echo "4. Checking .env file:"
if [ -f ".env" ]; then
    # Look for DISCORD_APPLICATION_ID in .env
    grep_result=$(grep "DISCORD_APPLICATION_ID" .env 2>/dev/null)
    if [ -z "$grep_result" ]; then
        echo "   DISCORD_APPLICATION_ID not found in .env file"
    else
        echo "   Found in .env file:"
        echo "$grep_result" | while IFS= read -r line; do
            echo "   Line: '$line'"
            # Check if line is commented
            if [[ "$line" =~ ^[[:space:]]*# ]]; then
                echo "   ⚠️  WARNING: Line is commented out"
            fi
        done
    fi
else
    echo "   No .env file found in current directory"
fi

echo ""
echo "5. Docker/Environment check:"
if [ -f "/.dockerenv" ]; then
    echo "   Running inside Docker container"
else
    echo "   Not running in Docker"
fi

# Check if running with docker-compose
if [ ! -z "$COMPOSE_PROJECT_NAME" ]; then
    echo "   Docker Compose project: $COMPOSE_PROJECT_NAME"
fi

echo ""
echo "6. Common issues summary:"
if [ ! -z "$DISCORD_APPLICATION_ID" ]; then
    issues=0
    
    # Check various issues
    if [[ "$DISCORD_APPLICATION_ID" != $(echo "$DISCORD_APPLICATION_ID" | xargs) ]]; then
        echo "   ❌ Remove whitespace from the value"
        ((issues++))
    fi
    
    if [[ "$DISCORD_APPLICATION_ID" == *\"* ]]; then
        echo "   ❌ Remove quotes from the value"
        ((issues++))
    fi
    
    if [[ ! "$DISCORD_APPLICATION_ID" =~ ^[0-9]+$ ]]; then
        echo "   ❌ Value should only contain numbers (0-9)"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        echo "   ✓ No obvious issues detected"
        echo "   The value appears to be correctly formatted"
    fi
else
    echo "   ❌ DISCORD_APPLICATION_ID is not set"
    echo ""
    echo "   To fix:"
    echo "   1. Add to .env file: DISCORD_APPLICATION_ID=your_app_id_here"
    echo "   2. Or export directly: export DISCORD_APPLICATION_ID=your_app_id_here"
fi

echo ""
echo "=== End of diagnostic ==="
echo ""
echo "If the value looks correct but still doesn't work:"
echo "1. Make sure to restart the application after setting the variable"
echo "2. If using Docker, ensure the variable is passed to the container"
echo "3. Check that .env file has Unix line endings (LF), not Windows (CRLF)"
echo ""