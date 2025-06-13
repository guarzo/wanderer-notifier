#!/usr/bin/env elixir

# List all registered Discord commands
IO.puts("📋 Listing Discord Commands...")
IO.puts("==============================\n")

app_id = System.get_env("DISCORD_APPLICATION_ID")

if app_id do
  IO.puts("Application ID: #{app_id}\n")
  
  case Nostrum.Api.get_global_application_commands(app_id) do
    {:ok, commands} ->
      IO.puts("✅ Found #{length(commands)} global command(s):\n")
      
      Enum.each(commands, fn cmd ->
        IO.puts("Command: /#{cmd.name}")
        IO.puts("  ID: #{cmd.id}")
        IO.puts("  Description: #{cmd.description}")
        IO.puts("  Type: #{cmd.type}")
        
        if cmd.options do
          IO.puts("  Subcommands:")
          Enum.each(cmd.options, fn opt ->
            IO.puts("    - #{opt.name}: #{opt.description}")
          end)
        end
        
        IO.puts("")
      end)
      
    {:error, error} ->
      IO.puts("❌ Failed to fetch commands: #{inspect(error)}")
  end
  
  # Also check guild-specific commands for the configured Discord channel
  channel_id = WandererNotifier.Config.discord_channel_id()
  if channel_id do
    IO.puts("\n📍 Checking guild commands for channel's guild...")
    # This would require fetching the guild ID from the channel first
    # For now, just note that global commands should work
    IO.puts("Note: Using global commands which work in all guilds where the bot is present")
  end
else
  IO.puts("❌ DISCORD_APPLICATION_ID not set")
end