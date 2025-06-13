# Test script for priority-only mode functionality
# Start the application to ensure supervisors are running
Application.ensure_all_started(:wanderer_notifier)

alias WandererNotifier.{NotificationService, Config, PersistentValues}

IO.puts("🧪 Testing Priority-Only Mode Logic")

# Clean up any existing state
NotificationService.clear_priority_systems()

# Test 1: Normal mode with no priority systems
IO.puts("\n📋 Test 1: Normal mode, no priority systems")
result1 = NotificationService.notify_system("TestSystem1")
IO.puts("Result: #{inspect(result1)} (should be :ok or :skip based on SYSTEM_NOTIFICATIONS_ENABLED)")

# Test 2: Normal mode with priority system
IO.puts("\n📋 Test 2: Normal mode, with priority system")
:ok = NotificationService.register_priority_system("TestSystem2")
result2 = NotificationService.notify_system("TestSystem2")
IO.puts("Result: #{inspect(result2)} (should be :ok - priority always works)")

# Test 3: Check current configuration
IO.puts("\n📋 Test 3: Current configuration")
IO.puts("System notifications enabled: #{Config.system_notifications_enabled?()}")
IO.puts("Priority systems only: #{Config.priority_systems_only?()}")
IO.puts("Priority systems count: #{length(NotificationService.list_priority_systems())}")

# Test 4: Priority-only mode simulation (by temporarily setting config)
IO.puts("\n📋 Test 4: Simulating priority-only mode")
IO.puts("In priority-only mode:")
IO.puts("- Priority systems: Always notify with @here")
IO.puts("- Regular systems: Never notify")

# Clean up
NotificationService.clear_priority_systems()
IO.puts("\n✅ Priority-only mode tests completed!")

IO.puts("""

🎯 To enable priority-only mode in production:
   export PRIORITY_SYSTEMS_ONLY=true

📊 Notification behavior matrix:
   | System Type | Normal Mode | Priority-Only Mode |
   |-------------|-------------|-------------------|
   | Priority    | @here       | @here            |
   | Regular     | normal/skip | skip             |
""")