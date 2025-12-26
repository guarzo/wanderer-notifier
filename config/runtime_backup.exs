import Config
alias WandererNotifier.Shared.Config.Utils

# This file provides compile-time configuration defaults.
# Runtime configuration is handled by WandererNotifier.Shared.Config.Provider
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
  system_update_scheduler_interval:
    WandererNotifier.Shared.Types.Constants.system_update_interval(),
  character_update_scheduler_interval:
    WandererNotifier.Shared.Types.Constants.character_update_interval()

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

    {feature_name, Utils.parse_bool(value, true)}
  end)
  |> Enum.into(%{})

config :wanderer_notifier,
  # Required settings
  map_token: System.get_env("MAP_API_KEY"),
  license_key: System.get_env("LICENSE_KEY"),
  map_url: System.get_env("MAP_URL"),
  map_name: System.get_env("MAP_NAME"),

  # Set discord_channel_id explicitly
  discord_channel_id: System.get_env("DISCORD_CHANNEL_ID") || "",
  discord_application_id: System.get_env("DISCORD_APPLICATION_ID"),
  discord_bot_token: System.get_env("DISCORD_BOT_TOKEN"),

  # Priority systems only mode
  priority_systems_only: Utils.parse_bool(System.get_env("PRIORITY_SYSTEMS_ONLY"), false),

  # Explicitly set config module
  config: WandererNotifier.Shared.Config,

  # Optional settings with sensible defaults
  port: Utils.parse_int(System.get_env("PORT"), 4000),
  discord_system_kill_channel_id: System.get_env("DISCORD_SYSTEM_KILL_CHANNEL_ID"),
  discord_character_kill_channel_id: System.get_env("DISCORD_CHARACTER_KILL_CHANNEL_ID"),
  discord_system_channel_id: System.get_env("DISCORD_SYSTEM_CHANNEL_ID"),
  discord_character_channel_id: System.get_env("DISCORD_CHARACTER_CHANNEL_ID"),
  license_manager_api_url: System.get_env("LICENSE_MANAGER_URL") || "https://lm.wanderer.ltd",
  # Merge base features with any feature env vars
  features:
    Map.merge(
      %{
        notifications_enabled: Utils.parse_bool(System.get_env("NOTIFICATIONS_ENABLED"), true),
        kill_notifications_enabled:
          Utils.parse_bool(System.get_env("KILL_NOTIFICATIONS_ENABLED"), true),
        system_notifications_enabled:
          Utils.parse_bool(System.get_env("SYSTEM_NOTIFICATIONS_ENABLED"), true),
        character_notifications_enabled:
          Utils.parse_bool(System.get_env("CHARACTER_NOTIFICATIONS_ENABLED"), true),
        status_messages_enabled: Utils.parse_bool(System.get_env("STATUS_MESSAGES_ENABLED"), false)
      },
      feature_env_vars
    ),
  character_exclude_list:
    System.get_env("CHARACTER_EXCLUDE_LIST")
    |> WandererNotifier.Shared.Config.Utils.parse_comma_list(),
  cache_dir: System.get_env("CACHE_DIR") || "/app/data/cache",
  public_url: System.get_env("PUBLIC_URL"),
  host: System.get_env("HOST") || "localhost",
  scheme: System.get_env("SCHEME") || "http"

# Configure the Phoenix endpoint
config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  url: [
    host: System.get_env("HOST") || "localhost",
    port: Utils.parse_int(System.get_env("PORT"), 4000),
    scheme: System.get_env("SCHEME") || "http"
  ],
  http: [
    port: Utils.parse_int(System.get_env("PORT"), 4000),
    transport_options: [socket_opts: [:inet6]]
  ],
  server: true,
  # Secret key base for signing sessions, cookies, and tokens
  # IMPORTANT: The default value below is for development only and should never be used in production
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "wanderer_notifier_secret_key_base_default_for_development_only",
  live_view: [
    signing_salt: System.get_env("LIVE_VIEW_SIGNING_SALT") || "wanderer_liveview_salt"
  ]

# Configure WebSocket and WandererKills settings
config :wanderer_notifier,
  websocket_url: System.get_env("WEBSOCKET_URL") || "ws://host.docker.internal:4004",
  wanderer_kills_base_url:
    System.get_env("WANDERER_KILLS_URL") || "http://host.docker.internal:4004"

# Configure SSE settings
config :wanderer_notifier,
  # SSE Configuration - always enabled, no toggles needed
  sse_reconnect_initial_delay:
    Utils.parse_int(System.get_env("SSE_RECONNECT_INITIAL_DELAY"), 1000),
  sse_reconnect_max_delay: Utils.parse_int(System.get_env("SSE_RECONNECT_MAX_DELAY"), 30000),
  sse_event_buffer_size: Utils.parse_int(System.get_env("SSE_EVENT_BUFFER_SIZE"), 1000)

# Configure cache directory
config :wanderer_notifier, :cache, directory: System.get_env("CACHE_DIR") || "/app/data/cache"

# Configure API token for non-production environments
# In production, this is set at compile time in prod.exs
# Use MIX_ENV environment variable since Mix.env() is not available at runtime
if System.get_env("MIX_ENV") != "prod" do
  config :wanderer_notifier, api_token: System.get_env("NOTIFIER_API_TOKEN") || "missing_token"
end
