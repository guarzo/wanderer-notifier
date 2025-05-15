import Config

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
      require Logger

      Logger.info(
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
  port: (System.get_env("PORT") || "4000") |> String.to_integer(),
  discord_system_kill_channel_id: System.get_env("WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID") || "",
  discord_character_kill_channel_id: System.get_env("WANDERER_CHARACTER_KILL_CHANNEL_ID") || "",
  discord_system_channel_id: System.get_env("WANDERER_SYSTEM_CHANNEL_ID") || "",
  discord_character_channel_id: System.get_env("WANDERER_CHARACTER_CHANNEL_ID") || "",
  license_manager_api_url:
    System.get_env("WANDERER_LICENSE_MANAGER_URL") || "https://lm.wanderer.ltd",
  features: %{
    notifications_enabled: System.get_env("WANDERER_NOTIFICATIONS_ENABLED") != "false",
    kill_notifications_enabled: System.get_env("WANDERER_KILL_NOTIFICATIONS_ENABLED") != "false",
    system_notifications_enabled:
      System.get_env("WANDERER_SYSTEM_NOTIFICATIONS_ENABLED") != "false",
    character_notifications_enabled:
      System.get_env("WANDERER_CHARACTER_NOTIFICATIONS_ENABLED") != "false",
    disable_status_messages: System.get_env("WANDERER_DISABLE_STATUS_MESSAGES") == "true",
    track_kspace: System.get_env("WANDERER_FEATURE_TRACK_KSPACE") != "false"
  },
  character_exclude_list:
    (System.get_env("WANDERER_CHARACTER_EXCLUDE_LIST") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1),
  websocket: %{
    reconnect_delay:
      (System.get_env("WANDERER_WEBSOCKET_RECONNECT_DELAY") || "5000") |> String.to_integer(),
    max_reconnects:
      (System.get_env("WANDERER_WEBSOCKET_MAX_RECONNECTS") || "20") |> String.to_integer(),
    reconnect_window:
      (System.get_env("WANDERER_WEBSOCKET_RECONNECT_WINDOW") || "3600") |> String.to_integer()
  },
  cache_dir: System.get_env("WANDERER_CACHE_DIR") || "/app/data/cache",
  public_url: System.get_env("WANDERER_PUBLIC_URL"),
  host: System.get_env("WANDERER_HOST") || "localhost",
  scheme: System.get_env("WANDERER_SCHEME") || "http"
