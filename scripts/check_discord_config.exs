#!/usr/bin/env elixir

# Script to check Discord configuration
IO.puts("🔍 Checking Discord Configuration...")
IO.puts("")

# Check environment variables
discord_bot_token = System.get_env("DISCORD_BOT_TOKEN")
discord_app_id = System.get_env("DISCORD_APPLICATION_ID")
discord_channel_id = System.get_env("DISCORD_CHANNEL_ID")

IO.puts("Environment Variables:")
IO.puts("----------------------")
IO.puts("DISCORD_BOT_TOKEN: #{if discord_bot_token, do: "✅ Set (#{String.slice(discord_bot_token, 0..10)}...)", else: "❌ Not set"}")
IO.puts("DISCORD_APPLICATION_ID: #{if discord_app_id, do: "✅ Set (#{discord_app_id})", else: "❌ Not set"}")
IO.puts("DISCORD_CHANNEL_ID: #{if discord_channel_id, do: "✅ Set (#{discord_channel_id})", else: "⚠️  Not set (optional)"}")
IO.puts("")

# Start the application to check runtime config
Application.ensure_all_started(:wanderer_notifier)

# Check application configuration
alias WandererNotifier.Config

IO.puts("Application Configuration:")
IO.puts("-------------------------")

try do
  app_id = Config.discord_application_id()
  IO.puts("discord_application_id: ✅ #{app_id}")
rescue
  e ->
    IO.puts("discord_application_id: ❌ #{Exception.message(e)}")
end

bot_token = Config.discord_bot_token()
IO.puts("discord_bot_token: #{if bot_token, do: "✅ Set", else: "❌ Not set"}")

IO.puts("")
IO.puts("Slash Command Registration Status:")
IO.puts("---------------------------------")

if discord_app_id do
  IO.puts("✅ Application ID is set - slash commands CAN be registered")
  IO.puts("")
  IO.puts("To register commands, the bot will:")
  IO.puts("1. Connect to Discord using the bot token")
  IO.puts("2. Register global slash commands using the application ID")
  IO.puts("3. Commands will be available in all servers where the bot is present")
else
  IO.puts("❌ Application ID is NOT set - slash commands CANNOT be registered")
  IO.puts("")
  IO.puts("To enable slash commands:")
  IO.puts("1. Go to https://discord.com/developers/applications")
  IO.puts("2. Select your application")
  IO.puts("3. Copy the Application ID from General Information")
  IO.puts("4. Set it as an environment variable:")
  IO.puts("   export DISCORD_APPLICATION_ID=\"your_id_here\"")
end

IO.puts("")
IO.puts("Bot Capabilities:")
IO.puts("----------------")
IO.puts("• Send notifications: #{if bot_token, do: "✅ Yes", else: "❌ No (bot token required)"}")
IO.puts("• Slash commands: #{if discord_app_id && bot_token, do: "✅ Yes", else: "❌ No"}")