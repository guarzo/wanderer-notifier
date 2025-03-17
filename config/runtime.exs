import Config
import Dotenvy

env_dir_prefix = Path.expand("..", __DIR__)

env_vars =
  source!([
    Path.absname(".env", env_dir_prefix),
    Path.absname(".#{config_env()}.env", env_dir_prefix),
    System.get_env()
  ])

Enum.each(env_vars, fn {key, value} ->
  System.put_env(key, value)
end)

token = System.get_env("DISCORD_BOT_TOKEN")
trimmed_token = if is_binary(token), do: String.trim(token), else: nil

if is_nil(trimmed_token) or trimmed_token == "" do
  raise "DISCORD_BOT_TOKEN environment variable is required but not set or is empty"
end

# Only set the runtime token for Nostrum
config :nostrum,
  token: trimmed_token

# Discord and Map Configuration
config :wanderer_notifier,
  discord_bot_token: trimmed_token,
  discord_channel_id: System.get_env("DISCORD_CHANNEL_ID"),
  map_url: System.get_env("MAP_URL"),
  map_name: System.get_env("MAP_NAME"),
  map_url_with_name: System.get_env("MAP_URL_WITH_NAME"),
  map_token: System.get_env("MAP_TOKEN")

# EVE Corp Tools API Configuration
config :wanderer_notifier,
  corp_tools_api_url: System.get_env("CORP_TOOLS_API_URL"),
  corp_tools_api_token: System.get_env("CORP_TOOLS_API_TOKEN")

# License Configuration
config :wanderer_notifier,
  license_key: System.get_env("LICENSE_KEY"),
  bot_api_token: System.get_env("BOT_API_TOKEN"),
  license_manager_api_url: System.get_env("LICENSE_MANAGER_API_URL")

# Web server configuration
config :wanderer_notifier,
  web_port: String.to_integer(System.get_env("PORT") || "4000")
