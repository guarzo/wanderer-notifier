#!/usr/bin/env elixir

# Test Discord connection and command registration
Application.ensure_all_started(:wanderer_notifier)

# Give it a moment to connect
Process.sleep(5000)

IO.puts("\n📊 Discord Connection Test Results:")
IO.puts("==================================")

# Check if commands are registered
alias WandererNotifier.Discord.CommandRegistrar

case CommandRegistrar.list_registered_commands() do
  {:ok, commands} ->
    IO.puts("✅ Successfully connected to Discord API")
    IO.puts("📋 Registered commands: #{length(commands)}")
    
    Enum.each(commands, fn cmd ->
      IO.puts("  • /#{cmd["name"]} - #{cmd["description"]}")
    end)
    
  {:error, :missing_application_id} ->
    IO.puts("❌ Cannot list commands: DISCORD_APPLICATION_ID not configured")
    
  {:error, reason} ->
    IO.puts("❌ Failed to list commands: #{inspect(reason)}")
end

# Check bot connection status via Nostrum
IO.puts("\n🤖 Bot Status:")
IO.puts("--------------")

# Try to get the bot user
case Nostrum.Api.get_current_user() do
  {:ok, user} ->
    IO.puts("✅ Bot connected as: #{user.username}##{user.discriminator}")
    IO.puts("   Bot ID: #{user.id}")
    
  {:error, reason} ->
    IO.puts("❌ Bot not connected: #{inspect(reason)}")
end

# Check gateway connection
IO.puts("\n🌐 Gateway Status:")
IO.puts("----------------")

# Nostrum doesn't expose gateway status directly, but we can check if we're receiving events
IO.puts("Check application logs for:")
IO.puts("  - 'Discord consumer ready' message")
IO.puts("  - 'Slash commands registered successfully' message")
IO.puts("  - Any error messages about registration")

IO.puts("\n💡 Next Steps:")
IO.puts("-------------")
IO.puts("1. If commands aren't registered, check the logs for errors")
IO.puts("2. Ensure both DISCORD_BOT_TOKEN and DISCORD_APPLICATION_ID are set")
IO.puts("3. Make sure the bot has the 'applications.commands' scope")
IO.puts("4. Verify the bot is in at least one Discord server")