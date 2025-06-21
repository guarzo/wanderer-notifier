import Config
alias WandererNotifier.Config.Helpers

# This file provides compile-time configuration defaults.
# Runtime configuration is handled by WandererNotifier.Config.Provider
# for releases, and by loading this file (with potential .env) in development.

# Load environment variables from .env file if it exists
# but do not override existing environment variables
import Dotenvy

# Load .env file and get all env vars as a map
env_vars =
  try do
    case source(".env") do
      {:ok, env_map} when is_map(env_map) -> env_map
      _ -> %{}
    end
  rescue
    e ->
      IO.puts(
        "No .env file found or error loading it: #{Exception.message(e)}. Using existing environment variables."
      )

      %{}
  end

# Set .env variables only if they aren't already present in the environment
Enum.each(env_vars, fn {k, v} ->
  case System.get_env(k) do
    nil -> System.put_env(k, v)
    _ -> :ok
  end
end)

# Discord bot configuration
config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN"),
  gateway_intents: [
    :guilds,
    :guild_messages
  ]

# Configure scheduler intervals
config :wanderer_notifier,
  system_update_scheduler_interval: WandererNotifier.Constants.system_update_interval(),
  character_update_scheduler_interval: WandererNotifier.Constants.character_update_interval()

# Load feature-specific environment variables (no longer using WANDERER_FEATURE_ prefix)
# Look for any environment variables ending with _ENABLED or common feature flag patterns
feature_env_vars =
  System.get_env()
  |> Enum.filter(fn {key, _} ->
    String.match?(key, ~r/(TRACK_|TRACKING_|_ENABLED$)/) and
      not String.starts_with?(key, "NOTIFICATIONS_") and
      not String.starts_with?(key, "KILL_") and
      not String.starts_with?(key, "SYSTEM_") and
      not String.starts_with?(key, "CHARACTER_")
  end)
  |> Enum.map(fn {key, value} ->
    feature_name =
      key
      |> String.downcase()
      |> String.to_atom()

    {feature_name, Helpers.parse_bool(value, true)}
  end)
  |> Enum.into(%{})

# Build map_url_with_name from required MAP_URL and MAP_NAME
map_url = System.get_env("MAP_URL")
map_name = System.get_env("MAP_NAME")

map_url_with_name =
  if map_url && map_name do
    base_url = String.trim_trailing(map_url, "/")
    "#{base_url}/?name=#{map_name}"
  else
    nil
  end

config :wanderer_notifier,
  # Required settings
  map_token: System.get_env("MAP_API_KEY"),
  license_key: System.get_env("LICENSE_KEY"),
  map_url_with_name: map_url_with_name,
  map_url: map_url,
  map_name: map_name,
  map_id: System.get_env("MAP_ID"),

  # Set discord_channel_id explicitly
  discord_channel_id: System.get_env("DISCORD_CHANNEL_ID") || "",
  discord_application_id: System.get_env("DISCORD_APPLICATION_ID"),
  discord_bot_token: System.get_env("DISCORD_BOT_TOKEN"),

  # Priority systems only mode
  priority_systems_only: Helpers.parse_bool(System.get_env("PRIORITY_SYSTEMS_ONLY"), false),

  # Explicitly set config module
  config: WandererNotifier.Config,

  # Optional settings with sensible defaults
  port: Helpers.parse_int(System.get_env("PORT"), 4000),
  discord_system_kill_channel_id: System.get_env("DISCORD_SYSTEM_KILL_CHANNEL_ID"),
  discord_character_kill_channel_id: System.get_env("DISCORD_CHARACTER_KILL_CHANNEL_ID"),
  discord_system_channel_id: System.get_env("DISCORD_SYSTEM_CHANNEL_ID"),
  discord_character_channel_id: System.get_env("DISCORD_CHARACTER_CHANNEL_ID"),
  license_manager_api_url: System.get_env("LICENSE_MANAGER_URL") || "https://lm.wanderer.ltd",
  # Merge base features with any feature env vars
  features:
    Map.merge(
      %{
        notifications_enabled: Helpers.parse_bool(System.get_env("NOTIFICATIONS_ENABLED"), true),
        kill_notifications_enabled:
          Helpers.parse_bool(System.get_env("KILL_NOTIFICATIONS_ENABLED"), true),
        system_notifications_enabled:
          Helpers.parse_bool(System.get_env("SYSTEM_NOTIFICATIONS_ENABLED"), true),
        character_notifications_enabled:
          Helpers.parse_bool(System.get_env("CHARACTER_NOTIFICATIONS_ENABLED"), true),
        status_messages_enabled:
          Helpers.parse_bool(System.get_env("ENABLE_STATUS_MESSAGES"), false)
      },
      feature_env_vars
    ),
  character_exclude_list:
    System.get_env("CHARACTER_EXCLUDE_LIST")
    |> WandererNotifier.Config.Utils.parse_comma_list(),
  cache_dir: System.get_env("CACHE_DIR") || "/app/data/cache",
  public_url: System.get_env("PUBLIC_URL"),
  host: System.get_env("HOST") || "localhost",
  scheme: System.get_env("SCHEME") || "http"

# Configure the web server
config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  url: [host: System.get_env("HOST") || "localhost"],
  http: [
    port: Helpers.parse_int(System.get_env("PORT"), 4000)
  ],
  server: true

# Configure WebSocket and WandererKills settings
config :wanderer_notifier,
  websocket_enabled: Helpers.parse_bool(System.get_env("WEBSOCKET_ENABLED"), true),
  websocket_url: System.get_env("WEBSOCKET_URL") || "ws://host.docker.internal:4004",
  websocket_map_url: System.get_env("WEBSOCKET_MAP_URL") || "ws://host.docker.internal:4444",
  phoenix_websocket_version: System.get_env("PHOENIX_WEBSOCKET_VERSION"),
  wanderer_kills_base_url:
    System.get_env("WANDERER_KILLS_BASE_URL") || "http://host.docker.internal:4004"

# Configure cache directory
config :wanderer_notifier, :cache, directory: System.get_env("CACHE_DIR") || "/app/data/cache"

# Configure RedisQ
config :wanderer_notifier, :redisq, %{
  enabled: Helpers.parse_bool(System.get_env("REDISQ_ENABLED"), true),
  url: System.get_env("REDISQ_URL") || "https://zkillredisq.stream/listen.php",
  poll_interval: Helpers.parse_int(System.get_env("REDISQ_POLL_INTERVAL"), 1000)
}

# Configure API token for non-production environments
# In production, this is set at compile time in prod.exs
# Use MIX_ENV environment variable since Mix.env() is not available at runtime
if System.get_env("MIX_ENV") != "prod" do
  config :wanderer_notifier, api_token: System.get_env("NOTIFIER_API_TOKEN") || "missing_token"
end
