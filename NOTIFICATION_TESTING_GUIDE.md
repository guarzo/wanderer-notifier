# Notification Testing User Guide

## Overview

This guide explains how to test notification formatting and delivery using the IEx console. The testing system allows you to:

- Test character and system notifications with real data from your cache
- Control how kill notifications are classified (character vs system kills)
- Debug notification issues with specific entities

## Getting Started

### 1. Start the Application

```bash
# In your terminal
make s
# or
iex -S mix

# Change global log level
  Logger.configure(level: :debug)  # Options: :debug, :info, :warning, :error
```

### 2. Set Up Testing Alias

```elixir
# In the IEx console
iex> alias WandererNotifier.Testing.NotificationTester, as: NT
```

## Testing Character Notifications

Character notifications are sent when new characters are added to tracking.

```elixir
# Test with real character ID (must exist in your cache)
iex> NT.test_character("2115754172")

# Test with integer ID (converted to string automatically)
iex> NT.test_character(2112625428)
```

**Note**: The character must exist in your system's cache. If the character ID is not found, you'll get an error message. This ensures you're testing with real data that matches your actual tracking setup.

## Testing System Notifications

System notifications are sent when new systems are added to tracking.

```elixir
# Test with real system ID (must exist in your cache)
iex> NT.test_system("30000142")  # Jita
iex> NT.test_system("31000001")  # A wormhole system

# Test with integer ID (converted to string automatically)  
iex> NT.test_system(30000142)
```

**Note**: The system must exist in your system's cache. If the system ID is not found, you'll get an error message. This ensures you're testing with real data that matches your actual tracking setup.

## Testing Killmail ID Processing

Process a specific killmail by ID through the full notification pipeline. This fetches the killmail data from the WandererKills service and processes it as a new notification.

```elixir
# Process killmail by ID (fetches from WandererKills service)
iex> NT.test_killmail_id("128825896")

WandererNotifier.Testing.NotificationTester.test_killmail_id(128825896)

# Also works with integer IDs
iex> NT.test_killmail_id(123456789)
```

**How it works**:
1. Fetches the full killmail data from the WandererKills service using the API
2. Processes the killmail through the normal notification pipeline
3. Checks if characters/systems are tracked and sends notifications accordingly
4. Respects all normal business rules (deduplication, tracking status, etc.)

**Note**: The killmail ID must exist in the WandererKills service. If not found, you'll get a `:not_found` error.

## Kill Classification Override

**This is the key feature** - control how the next real kill from your data stream is classified.

### Set Character Kill Override

```elixir
# Force the next kill to be treated as a character kill
iex> NT.set_kill_override(:character)
```

Now when a real kill comes through your killmail processing pipeline, it will:
- Be treated as a character kill regardless of actual tracking status
- Route to the character kill Discord channel
- Follow character kill notification rules

### Set System Kill Override

```elixir
# Force the next kill to be treated as a system kill
iex> NT.set_kill_override(:system)
```

The next real kill will:
- Be treated as a system kill regardless of actual tracking status  
- Route to the system kill Discord channel
- Follow system kill notification rules

### Check and Clear Override

```elixir
# Check current override setting
iex> NT.get_kill_override()

# Clear any override (return to normal logic)
iex> NT.set_kill_override(:clear)
```

### How Override Works

1. You set an override: `:character` or `:system`
2. The override is stored in cache with a 10-minute expiration
3. When the next kill arrives through normal processing:
   - The system checks for the override
   - Forces classification based on the override
   - Routes to the appropriate Discord channel
   - Automatically clears the override after use

## Common Use Cases

### 1. Testing Notification Format Changes

When you modify notification formatting code:

```elixir
# Test the specific notification type you changed
iex> NT.test_character("2112625428")  # Use real character ID
iex> NT.test_system("30000142")       # Use real system ID
```

### 2. Testing Channel Routing

To verify kills route to the correct Discord channels:

```elixir
# Test character kill routing
iex> NT.set_kill_override(:character)
# Wait for a real kill to arrive, check it goes to character channel

# Test system kill routing
iex> NT.set_kill_override(:system)  
# Wait for a real kill to arrive, check it goes to system channel
```

### 3. Debugging Notification Issues

When notifications aren't working for specific entities:

```elixir
# Test specific character having issues
iex> NT.test_character("2112625428")  # Use the problematic character ID

# Test specific system having issues
iex> NT.test_system("31000005")  # Use the problematic system ID

# Test specific killmail that should have triggered notifications
iex> NT.test_killmail_id("123456789")  # Use the problematic killmail ID
```

### 4. Testing Edge Cases

```elixir
# Test characters/systems that might have unusual data
iex> NT.test_character("123456789")  # Character with minimal data
iex> NT.test_system("31000001")      # Wormhole system
```

## Understanding the Output

When you run tests, you'll see:

### Console Logs
```
[info] [TEST] Testing character notification for ID: 123456789
[info] [TEST] Found character: John Pilot  
[info] Character John Pilot (123456789) notified
```

### Discord Messages
- Character/system notifications will appear in your configured Discord channels
- In test environment, they appear as log messages instead

### Override Messages
```
[info] [TEST] Kill override set to :character (expires in 10 minutes)
[info] [TEST] Kill override: forcing character kill
[info] [TEST] Kill override: routing to character channel
```

## Tips and Best Practices

### 1. Use Aliases
Always set up the alias to save typing:
```elixir
iex> alias WandererNotifier.Testing.NotificationTester, as: NT
```

### 2. Test Before and After Changes
```elixir
# Before making changes
iex> NT.test_character("2119878082")

# Make your changes to notification formatting...

# After making changes
iex> NT.test_character("2112625428")
```

### 3. Clear Overrides When Done
```elixir
# Always clear overrides when finished testing
iex> NT.set_kill_override(:clear)
```

### 4. Use Real IDs from Your System
Find character and system IDs from your actual cache data to ensure realistic testing.

## Troubleshooting

### "Function not found" errors
Make sure you've started the application and set up the alias:
```elixir
iex> Application.ensure_all_started(:wanderer_notifier)
iex> alias WandererNotifier.Testing.NotificationTester, as: NT
```

### "Character/System not found" errors
The ID must exist in your cache. Check your cache contents or use different IDs that are actually tracked by your system.

### "Killmail not found" errors
The killmail ID must exist in the WandererKills service. Try using a more recent killmail ID or check that the WandererKills service is accessible.

### Override not working
Check that the override is set:
```elixir
iex> NT.get_kill_override()
```

Remember overrides expire after 10 minutes and are cleared after first use.

### No Discord messages appearing
- Check that Discord is configured correctly
- In test environment, messages appear as logs instead of Discord
- Verify the Discord channels are set in configuration

## Advanced Usage

### Testing with Real Cache Data
The system will automatically use real character/system data from cache:

```elixir
# This will use real data if character 2112625428 exists in cache
iex> NT.test_character("2112625428")
```

### Creating Repeatable Test Scenarios
```elixir
# Create a function for your common test scenario
iex> test_scenario = fn ->
...>   NT.test_character("2112625428")
...>   NT.test_system("30000142")  
...>   NT.test_killmail_id("123456789")
...>   NT.set_kill_override(:character)
...> end
iex> test_scenario.()
```

This testing system provides a simple but powerful way to verify that your notification formatting and routing logic works correctly using real data from your system.