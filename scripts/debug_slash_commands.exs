#!/usr/bin/env elixir

# Debug script for slash command issues
IO.puts("🔍 Debugging Slash Commands...")
IO.puts("================================\n")

# Set debug logging
WandererNotifier.Config.enable_debug_logging()
IO.puts("✅ Debug logging enabled\n")

# Check bot connection
IO.puts("1️⃣ Checking bot connection...")
case Nostrum.Api.get_current_user() do
  {:ok, bot} ->
    IO.puts("✅ Bot connected as: #{bot.username}##{bot.discriminator}")
    IO.puts("   Bot ID: #{bot.id}")
    
  {:error, reason} ->
    IO.puts("❌ Bot not connected: #{inspect(reason)}")
end

# Check application ID
IO.puts("\n2️⃣ Checking application ID...")
try do
  app_id = WandererNotifier.Config.discord_application_id()
  IO.puts("✅ Application ID configured: #{app_id}")
rescue
  e ->
    IO.puts("❌ Application ID not configured: #{Exception.message(e)}")
end

# Check gateway intents
IO.puts("\n3️⃣ Checking gateway intents...")
intents = Application.get_env(:nostrum, :gateway_intents, [])
IO.puts("✅ Gateway intents: #{inspect(intents)}")

# Check if Consumer is started
IO.puts("\n4️⃣ Checking if Consumer is running...")
children = Supervisor.which_children(WandererNotifier.Supervisor)
consumer_running = Enum.any?(children, fn
  {WandererNotifier.Discord.Consumer, _, _, _} -> true
  _ -> false
end)

if consumer_running do
  IO.puts("✅ Discord.Consumer is running")
else
  IO.puts("❌ Discord.Consumer is NOT running")
end

IO.puts("\n📋 Next Steps:")
IO.puts("1. Make sure bot was invited with 'applications.commands' scope")
IO.puts("2. Try typing /notifier in Discord and watch the logs")
IO.puts("3. Check for 'INTERACTION_CREATE event received' in logs")
IO.puts("4. If no logs appear, the bot isn't receiving events from Discord")