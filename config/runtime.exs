import Config
import Dotenvy

env_dir_prefix = Path.expand("..", __DIR__)

env_vars = source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{config_env()}.env", env_dir_prefix),
  System.get_env()
])

Enum.each(env_vars, fn {key, value} ->
  System.put_env(key, value)
end)

# Retrieve the Discord bot token
token = System.get_env("DISCORD_BOT_TOKEN")
trimmed_token = if is_binary(token), do: String.trim(token), else: nil
IO.inspect(trimmed_token, label: "Trimmed DISCORD_BOT_TOKEN")

config :nostrum,
  token: trimmed_token

config :chainkills,
  map_url: System.get_env("MAP_URL"),
  map_name: System.get_env("MAP_NAME"),
  map_token: System.get_env("MAP_TOKEN"),
  discord_bot_token: trimmed_token,
  discord_channel_id: System.get_env("DISCORD_CHANNEL_ID"),
  zkill_base_url: System.get_env("ZKILL_BASE_URL"),
  esi_base_url: System.get_env("ESI_BASE_URL")
