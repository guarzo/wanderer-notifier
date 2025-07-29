#!/usr/bin/env elixir

# Minimal test to see if Discord is connecting
IO.puts("Starting minimal Discord test...")

# Start only the necessary applications
Application.ensure_all_started(:nostrum)

# Wait a moment for connection
Process.sleep(3000)

# Try to get bot info
case Nostrum.Api.get_current_user() do
  {:ok, user} ->
    IO.puts("✅ Bot connected as: #{user.username}##{user.discriminator}")
    IO.puts("   Bot ID: #{user.id}")
    
    # Now try to get the application info
    app_id = System.get_env("DISCORD_APPLICATION_ID")
    
    if app_id do
      IO.puts("\n📱 Application ID: #{app_id}")
      
      # Try to list existing commands
      case Nostrum.Api.get_global_application_commands(app_id) do
        {:ok, commands} ->
          IO.puts("📋 Existing global commands: #{length(commands)}")
          Enum.each(commands, fn cmd ->
            IO.puts("  • /#{cmd.name}")
          end)
          
        {:error, reason} ->
          IO.puts("❌ Failed to list commands: #{inspect(reason)}")
      end
    else
      IO.puts("❌ No DISCORD_APPLICATION_ID set")
    end
    
  {:error, %{status_code: 401}} ->
    IO.puts("❌ Invalid bot token (401 Unauthorized)")
    IO.puts("   Check that DISCORD_BOT_TOKEN is correct")
    
  {:error, reason} ->
    IO.puts("❌ Failed to connect: #{inspect(reason)}")
end