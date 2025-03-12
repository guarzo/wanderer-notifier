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

config :nostrum,
  token: trimmed_token

# Commented out chainkills configuration as it's not available
# If you need this configuration, please add the chainkills dependency to mix.exs
# config :chainkills,
#   map_url: System.get_env("MAP_URL"),
#   map_name: System.get_env("MAP_NAME"),
#   map_token: System.get_env("MAP_TOKEN"),
#   discord_bot_token: trimmed_token,
#   discord_channel_id: System.get_env("DISCORD_CHANNEL_ID"),
#   zkill_base_url: System.get_env("ZKILL_BASE_URL"),
#   esi_base_url: System.get_env("ESI_BASE_URL")

# Discord and Map Configuration
config :wanderer_notifier,
  discord_bot_token: trimmed_token,
  discord_channel_id: System.get_env("DISCORD_CHANNEL_ID"),
  map_url: System.get_env("MAP_URL"),
  map_name: System.get_env("MAP_NAME"),
  map_url_with_name: System.get_env("MAP_URL_WITH_NAME"),
  map_token: System.get_env("MAP_TOKEN")

# License Configuration
config :wanderer_notifier,
  license_key: System.get_env("LICENSE_KEY"),
  bot_id: System.get_env("BOT_ID")

# Development overrides
if config_env() == :dev do
  config :wanderer_notifier,
    license_manager_api_url: System.get_env("LICENSE_MANAGER_API_URL")
end

# Web server configuration
config :wanderer_notifier,
  web_port: String.to_integer(System.get_env("WEB_PORT") || "8080")
