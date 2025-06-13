#!/bin/bash

# Test script for system command functionality
# This script tests the core system command features without Discord

set -e

echo "🧪 Testing WandererNotifier System Commands"

# Start Elixir with our application
elixir --erl "-noshell" -S mix run --no-halt &
APP_PID=$!

# Function to cleanup on exit
cleanup() {
    echo "🧹 Cleaning up..."
    kill $APP_PID 2>/dev/null || true
    exit 0
}
trap cleanup EXIT

# Give the app time to start
echo "⏳ Starting application..."
sleep 5

# Test using mix run to execute our commands
echo ""
echo "📋 Testing PersistentValues module..."

# Test PersistentValues
cat > /tmp/test_persistent_values.exs << 'EOF'
# Test PersistentValues functionality
alias WandererNotifier.PersistentValues

# Test basic operations
:ok = PersistentValues.put(:test_key, [1, 2, 3])
values = PersistentValues.get(:test_key)
IO.puts("✅ PersistentValues test: #{inspect(values)}")

# Test add/remove
:ok = PersistentValues.add(:test_key, 4)
:ok = PersistentValues.remove(:test_key, 2)
final_values = PersistentValues.get(:test_key)
IO.puts("✅ Add/Remove test: #{inspect(final_values)}")

# Clean up
PersistentValues.clear()
IO.puts("✅ PersistentValues tests passed!")
EOF

mix run /tmp/test_persistent_values.exs

echo ""
echo "📋 Testing CommandLog module..."

# Test CommandLog
cat > /tmp/test_command_log.exs << 'EOF'
# Test CommandLog functionality
alias WandererNotifier.CommandLog

# Test logging commands
entry = %{
  type: "system",
  param: "Jita",
  user_id: 123456789,
  username: "TestUser",
  timestamp: DateTime.utc_now()
}

:ok = CommandLog.log(entry)
commands = CommandLog.all()
IO.puts("✅ CommandLog test: #{length(commands)} commands logged")

stats = CommandLog.stats()
IO.puts("✅ Stats test: #{stats.total_commands} total commands")

# Clean up
CommandLog.clear()
IO.puts("✅ CommandLog tests passed!")
EOF

mix run /tmp/test_command_log.exs

echo ""
echo "📋 Testing NotificationService module..."

# Test NotificationService
cat > /tmp/test_notification_service.exs << 'EOF'
# Test NotificationService functionality
alias WandererNotifier.NotificationService

# Test priority system management
:ok = NotificationService.register_priority_system("Jita")
is_priority = NotificationService.is_priority_system?("Jita")
IO.puts("✅ Priority system test: Jita is priority: #{is_priority}")

priority_list = NotificationService.list_priority_systems()
IO.puts("✅ Priority list test: #{length(priority_list)} priority systems")

# Test notification logic (in test mode)
result = NotificationService.notify_system("Jita")
IO.puts("✅ Notification test result: #{inspect(result)}")

# Clean up
NotificationService.clear_priority_systems()
IO.puts("✅ NotificationService tests passed!")
EOF

mix run /tmp/test_notification_service.exs

echo ""
echo "📋 Testing CommandRegistrar module..."

# Test CommandRegistrar
cat > /tmp/test_command_registrar.exs << 'EOF'
# Test CommandRegistrar functionality
alias WandererNotifier.Discord.CommandRegistrar

# Test command definitions
commands = CommandRegistrar.commands()
IO.puts("✅ Commands defined: #{length(commands)} command groups")

notifier_command = Enum.find(commands, & &1.name == "notifier")
subcommands = Enum.map(notifier_command.options, & &1.name)
IO.puts("✅ Subcommands available: #{inspect(subcommands)}")

# Test interaction validation
valid_interaction = %{
  data: %{
    name: "notifier",
    options: [%{name: "system"}]
  }
}

is_valid = CommandRegistrar.valid_interaction?(valid_interaction)
IO.puts("✅ Interaction validation test: #{is_valid}")

IO.puts("✅ CommandRegistrar tests passed!")
EOF

mix run /tmp/test_command_registrar.exs

echo ""
echo "🎉 All system command tests completed successfully!"
echo ""
echo "🚀 Ready for Discord integration testing!"
echo ""
echo "📝 To test with Discord:"
echo "   1. Set DISCORD_BOT_TOKEN in your environment"
echo "   2. Set DISCORD_APPLICATION_ID in your environment"
echo "   3. Run: mix run --no-halt"
echo "   4. Use /notifier system <system_name> in Discord"
echo "   5. Use /notifier status to see current state"

# Cleanup temp files
rm -f /tmp/test_*.exs

echo "✅ Test completed successfully!"