import Config

# Helper function for safely parsing integers from environment variables
defp parse_int(value, default) when is_binary(value) do
  case Integer.parse(String.trim(value)) do
    {int, _} -> int
    :error -> default
  end
end

defp parse_int(nil, default), do: default
defp parse_int(value, default) when is_integer(value), do: value
defp parse_int(_, default), do: default

# Helper function for parsing boolean values
defp parse_bool(value, default) when is_binary(value) do
  case String.downcase(String.trim(value)) do
    "true" -> true
    "false" -> false
    _ -> default
  end
end

defp parse_bool(nil, default), do: default
defp parse_bool(value, _) when is_boolean(value), do: value
defp parse_bool(_, default), do: default

# This file provides compile-time configuration defaults.
# Runtime configuration is handled by WandererNotifier.ConfigProvider
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

# Base configuration with defaults
# These will be used in dev/test and as fallbacks in production
config :nostrum,
  token: System.get_env("WANDERER_DISCORD_BOT_TOKEN") || "missing_token"

config :wanderer_notifier,
  # Required settings (will raise at runtime if not set in production)
  map_token: System.get_env("WANDERER_MAP_TOKEN") || "missing_token",
  api_token: System.get_env("WANDERER_NOTIFIER_API_TOKEN") || "missing_token",
  license_key: System.get_env("WANDERER_LICENSE_KEY") || "missing_key",
  map_url_with_name: System.get_env("WANDERER_MAP_URL") || "missing_url",
  discord_channel_id: System.get_env("WANDERER_DISCORD_CHANNEL_ID") || "missing_channel_id",

  # Optional settings with sensible defaults
  port: parse_int(System.get_env("PORT"), 4000),
  discord_system_kill_channel_id: System.get_env("WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID") || "",
  discord_character_kill_channel_id: System.get_env("WANDERER_CHARACTER_KILL_CHANNEL_ID") || "",
  discord_system_channel_id: System.get_env("WANDERER_SYSTEM_CHANNEL_ID") || "",
  discord_character_channel_id: System.get_env("WANDERER_CHARACTER_CHANNEL_ID") || "",
  license_manager_api_url:
    System.get_env("WANDERER_LICENSE_MANAGER_URL") || "https://lm.wanderer.ltd",
  features: %{
    notifications_enabled: parse_bool(System.get_env("WANDERER_NOTIFICATIONS_ENABLED"), true),
    kill_notifications_enabled:
      parse_bool(System.get_env("WANDERER_KILL_NOTIFICATIONS_ENABLED"), true),
    system_notifications_enabled:
      parse_bool(System.get_env("WANDERER_SYSTEM_NOTIFICATIONS_ENABLED"), true),
    character_notifications_enabled:
      parse_bool(System.get_env("WANDERER_CHARACTER_NOTIFICATIONS_ENABLED"), true),
    disable_status_messages:
      parse_bool(System.get_env("WANDERER_DISABLE_STATUS_MESSAGES"), false),
    track_kspace: parse_bool(System.get_env("WANDERER_FEATURE_TRACK_KSPACE"), true)
  },
  character_exclude_list:
    (System.get_env("WANDERER_CHARACTER_EXCLUDE_LIST") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1),
  websocket: %{
    reconnect_delay: parse_int(System.get_env("WANDERER_WEBSOCKET_RECONNECT_DELAY"), 5000),
    max_reconnects: parse_int(System.get_env("WANDERER_WEBSOCKET_MAX_RECONNECTS"), 20),
    reconnect_window: parse_int(System.get_env("WANDERER_WEBSOCKET_RECONNECT_WINDOW"), 3600)
  },
  cache_dir: System.get_env("WANDERER_CACHE_DIR") || "/app/data/cache",
  public_url: System.get_env("WANDERER_PUBLIC_URL"),
  host: System.get_env("WANDERER_HOST") || "localhost",
  scheme: System.get_env("WANDERER_SCHEME") || "http"

# Configure the web server
config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  url: [host: System.get_env("WANDERER_HOST", "localhost")],
  http: [
    port: parse_int(System.get_env("PORT"), 4000)
  ],
  server: true

# Configure WebSocket settings
config :wanderer_notifier, :websocket,
  url: System.get_env("WANDERER_WS_URL", "wss://zkillboard.com/websocket/"),
  reconnect_delay: parse_int(System.get_env("WANDERER_WS_RECONNECT_DELAY_MS"), 5000),
  max_reconnects: parse_int(System.get_env("WANDERER_WS_MAX_RECONNECTS"), 20),
  reconnect_window: parse_int(System.get_env("WANDERER_WS_RECONNECT_WINDOW_MS"), 3600)

# Configure cache directory
config :wanderer_notifier, :cache,
  directory: System.get_env("WANDERER_CACHE_DIR", "/app/data/cache")

# Configure feature flags
config :wanderer_notifier, :features,
  notifications_enabled: parse_bool(System.get_env("WANDERER_NOTIFICATIONS_ENABLED"), true),
  kill_notifications_enabled:
    parse_bool(System.get_env("WANDERER_KILL_NOTIFICATIONS_ENABLED"), true),
  system_notifications_enabled:
    parse_bool(System.get_env("WANDERER_SYSTEM_NOTIFICATIONS_ENABLED"), true),
  character_notifications_enabled:
    parse_bool(System.get_env("WANDERER_CHARACTER_NOTIFICATIONS_ENABLED"), true),
  disable_status_messages: parse_bool(System.get_env("WANDERER_DISABLE_STATUS_MESSAGES"), false),
  track_kspace: parse_bool(System.get_env("WANDERER_FEATURE_TRACK_KSPACE"), true)
