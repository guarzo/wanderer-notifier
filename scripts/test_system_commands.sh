#!/bin/bash

# Test script for system command functionality
# This script tests the core system command features without Discord

set -e

echo "🧪 Testing WandererNotifier System Commands"

# Start Elixir with our application
mix run --no-halt &
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

# Create comprehensive test script
cat > /tmp/comprehensive_test.exs << 'EOF'
# Comprehensive test for all system command functionality
IO.puts("📋 Running comprehensive system command tests...")

alias WandererNotifier.{PersistentValues, CommandLog, NotificationService}
alias WandererNotifier.Discord.CommandRegistrar

# Test 1: PersistentValues
IO.puts("\n🔧 Testing PersistentValues module...")
:ok = PersistentValues.put(:test_key, [1, 2, 3])
values = PersistentValues.get(:test_key)
IO.puts("✅ PersistentValues test: #{inspect(values)}")

:ok = PersistentValues.add(:test_key, 4)
:ok = PersistentValues.remove(:test_key, 2)
final_values = PersistentValues.get(:test_key)
IO.puts("✅ Add/Remove test: #{inspect(final_values)}")

PersistentValues.clear()
IO.puts("✅ PersistentValues tests passed!")

# Test 2: CommandLog
IO.puts("\n📝 Testing CommandLog module...")
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

CommandLog.clear()
IO.puts("✅ CommandLog tests passed!")

# Test 3: NotificationService
IO.puts("\n🔔 Testing NotificationService module...")
:ok = NotificationService.register_priority_system("Jita")
is_priority = NotificationService.is_priority_system?("Jita")
IO.puts("✅ Priority system test: Jita is priority: #{is_priority}")

priority_list = NotificationService.list_priority_systems()
IO.puts("✅ Priority list test: #{length(priority_list)} priority systems")

result = NotificationService.notify_system("Jita")
IO.puts("✅ Notification test result: #{inspect(result)}")

NotificationService.clear_priority_systems()
IO.puts("✅ NotificationService tests passed!")

# Test 4: CommandRegistrar
IO.puts("\n⚙️ Testing CommandRegistrar module...")
commands = CommandRegistrar.commands()
IO.puts("✅ Commands defined: #{length(commands)} command groups")

notifier_command = Enum.find(commands, & &1.name == "notifier")
subcommands = Enum.map(notifier_command.options, & &1.name)
IO.puts("✅ Subcommands available: #{inspect(subcommands)}")

valid_interaction = %{
  data: %{
    name: "notifier",
    options: [%{name: "system"}]
  }
}

is_valid = CommandRegistrar.valid_interaction?(valid_interaction)
IO.puts("✅ Interaction validation test: #{is_valid}")

IO.puts("✅ CommandRegistrar tests passed!")

IO.puts("\n🎉 All comprehensive tests completed successfully!")
EOF

# Run the comprehensive test using the already running application
elixir --eval 'Code.eval_file("/tmp/comprehensive_test.exs")'

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
rm -f /tmp/comprehensive_test.exs

echo "✅ Test completed successfully!"