#!/usr/bin/env elixir

# Debug Discord command issues
IO.puts("🔍 Debugging Discord Slash Commands...")
IO.puts("=====================================\n")

# Start the application
Application.ensure_all_started(:wanderer_notifier)
Process.sleep(3000)

# 1. Check bot connection
IO.puts("1️⃣ Bot Connection Status:")
IO.puts("-----------------------")
case Nostrum.Api.get_current_user() do
  {:ok, bot} ->
    IO.puts("✅ Bot connected as: #{bot.username}##{bot.discriminator}")
    IO.puts("   Bot ID: #{bot.id}")
    bot_id = bot.id
    
    # 2. Check registered commands
    IO.puts("\n2️⃣ Registered Commands:")
    IO.puts("---------------------")
    app_id = System.get_env("DISCORD_APPLICATION_ID")
    
    case Nostrum.Api.get_global_application_commands(app_id) do
      {:ok, commands} ->
        IO.puts("✅ Found #{length(commands)} global commands:")
        Enum.each(commands, fn cmd ->
          IO.puts("   • /#{cmd.name} (ID: #{cmd.id})")
          IO.puts("     Description: #{cmd.description}")
          if cmd.options do
            IO.puts("     Subcommands: #{Enum.map(cmd.options, & &1.name) |> Enum.join(", ")}")
          end
        end)
        
      {:error, reason} ->
        IO.puts("❌ Failed to list commands: #{inspect(reason)}")
    end
    
    # 3. Check bot permissions
    IO.puts("\n3️⃣ Bot Invite URL:")
    IO.puts("----------------")
    IO.puts("Make sure your bot was invited with these permissions:")
    IO.puts("https://discord.com/api/oauth2/authorize?client_id=#{app_id}&permissions=2147485696&scope=bot%20applications.commands")
    IO.puts("")
    IO.puts("Required scopes: bot, applications.commands")
    IO.puts("Required permissions: Send Messages, Use Slash Commands")
    
    # 4. Check if bot is in guilds
    IO.puts("\n4️⃣ Guild Membership:")
    IO.puts("------------------")
    case Nostrum.Cache.Me.get() do
      %{guilds: guilds} when is_list(guilds) ->
        IO.puts("Bot is in #{length(guilds)} guild(s)")
      _ ->
        IO.puts("⚠️  Cannot determine guild membership")
    end
    
  {:error, reason} ->
    IO.puts("❌ Bot not connected: #{inspect(reason)}")
end

# 5. Common issues
IO.puts("\n5️⃣ Troubleshooting Checklist:")
IO.puts("---------------------------")
IO.puts("□ Bot has 'applications.commands' scope")
IO.puts("□ Bot has 'Use Slash Commands' permission in the server")
IO.puts("□ You've waited 1-2 minutes for commands to sync")
IO.puts("□ You've refreshed Discord (Ctrl+R / Cmd+R)")
IO.puts("□ Commands show in Discord's command menu (type /)")
IO.puts("□ Bot is online and shows as active in the member list")

IO.puts("\n6️⃣ If Commands Still Don't Work:")
IO.puts("-------------------------------")
IO.puts("1. Kick and re-invite the bot with the URL above")
IO.puts("2. Try in a different channel")
IO.puts("3. Check if the bot responds to the INTERACTION_CREATE event")
IO.puts("   (check logs for 'Received invalid interaction' messages)")

# Check if we're receiving any events
IO.puts("\n7️⃣ Event Reception Test:")
IO.puts("----------------------")
IO.puts("Try using a slash command now and check the logs for:")
IO.puts("• 'Received invalid interaction' - means bot sees the command")
IO.puts("• 'Discord command executed' - means command was processed")
IO.puts("• No logs - means Discord isn't sending events to the bot")