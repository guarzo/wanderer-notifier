#!/usr/bin/env elixir

# Check bot permissions and guild membership
IO.puts("🔍 Checking Bot Permissions...")
IO.puts("==============================\n")

# Get bot info
case Nostrum.Api.get_current_user() do
  {:ok, bot} ->
    IO.puts("✅ Bot: #{bot.username}##{bot.discriminator}")
    bot_id = bot.id
    
    # Get application info
    app_id = System.get_env("DISCORD_APPLICATION_ID")
    
    # List guilds
    IO.puts("\n📋 Guild Memberships:")
    case Nostrum.Api.get_current_user_guilds() do
      {:ok, guilds} ->
        Enum.each(guilds, fn guild ->
          IO.puts("  • #{guild.name} (ID: #{guild.id})")
          
          # Try to get the bot's member info in this guild
          case Nostrum.Api.get_guild_member(guild.id, bot_id) do
            {:ok, member} ->
              IO.puts("    Roles: #{Enum.join(member.roles, ", ")}")
              
            {:error, _} ->
              IO.puts("    ❌ Cannot fetch member info")
          end
        end)
        
      {:error, reason} ->
        IO.puts("❌ Failed to list guilds: #{inspect(reason)}")
    end
    
    # Show invite URL
    IO.puts("\n🔗 Bot Invite URL:")
    IO.puts("Make sure you used this URL to invite the bot:")
    IO.puts("https://discord.com/api/oauth2/authorize?client_id=#{app_id}&permissions=2147485696&scope=bot%20applications.commands")
    IO.puts("")
    IO.puts("Required scopes:")
    IO.puts("  ✅ bot")
    IO.puts("  ✅ applications.commands")
    IO.puts("")
    IO.puts("Required permissions:")
    IO.puts("  ✅ Send Messages")
    IO.puts("  ✅ Use Slash Commands")
    
  {:error, reason} ->
    IO.puts("❌ Bot not connected: #{inspect(reason)}")
end