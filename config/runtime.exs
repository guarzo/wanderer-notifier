import Config
import Dotenvy

# Helper to safely parse port number from environment variable
safe_parse_port = fn
  port_str, default when is_binary(port_str) ->
    case Integer.parse(port_str) do
      {port, ""} when port > 0 and port < 65_536 ->
        port

      _ ->
        require Logger
        Logger.warning("Invalid PORT value: '#{port_str}', using default: #{default}")
        default
    end

  _nil_or_other, default ->
    default
end

# Helper to fetch required env vars or raise
fetch_env! = fn var ->
  System.get_env(var) || raise("Missing ENV: #{var}")
end

# Load .env file and get all env vars as a map
env_vars =
  try do
    # Use source instead of source! to avoid crashing if .env file is missing
    # Handle the {:ok, map} tuple that source/1 returns
    case source(".env") do
      {:ok, env_map} when is_map(env_map) -> env_map
      _ -> %{}
    end
  rescue
    # Handle any errors gracefully for production environments
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
    # Skip if env var is already set, even to empty string
    _ -> :ok
  end
end)

# Helper to parse boolean env vars using a map lookup for efficiency
parse_bool = fn var, default ->
  val = System.get_env(var)

  # If nil or empty, return the default
  if val == nil or val == "" do
    default
  else
    # Use a map lookup for constant-time comparison
    %{
      "true" => true,
      "1" => true,
      "yes" => true,
      "y" => true,
      "t" => true,
      "on" => true,
      "false" => false,
      "0" => false,
      "no" => false,
      "n" => false,
      "f" => false,
      "off" => false
    }[String.downcase(val)] || default
  end
end

config :nostrum,
  token: fetch_env!.("WANDERER_DISCORD_BOT_TOKEN")

config :wanderer_notifier,
  map_token: fetch_env!.("WANDERER_MAP_TOKEN"),
  api_token: fetch_env!.("WANDERER_NOTIFIER_API_TOKEN"),
  license_key: fetch_env!.("WANDERER_LICENSE_KEY"),
  map_url_with_name: fetch_env!.("WANDERER_MAP_URL"),
  discord_channel_id: fetch_env!.("WANDERER_DISCORD_CHANNEL_ID"),
  port: safe_parse_port.(System.get_env("PORT"), 4000),
  discord_system_kill_channel_id: System.get_env("WANDERER_DISCORD_SYSTEM_KILL_CHANNEL_ID") || "",
  discord_character_kill_channel_id: System.get_env("WANDERER_CHARACTER_KILL_CHANNEL_ID") || "",
  discord_system_channel_id: System.get_env("WANDERER_SYSTEM_CHANNEL_ID") || "",
  discord_character_channel_id: System.get_env("WANDERER_CHARACTER_CHANNEL_ID") || "",
  kill_channel_id: System.get_env("WANDERER_DISCORD_KILL_CHANNEL_ID") || "",
  license_manager_api_url: fetch_env!.("WANDERER_LICENSE_MANAGER_URL"),
  features: %{
    notifications_enabled: parse_bool.("WANDERER_NOTIFICATIONS_ENABLED", true),
    character_notifications_enabled:
      parse_bool.("WANDERER_CHARACTER_NOTIFICATIONS_ENABLED", true),
    system_notifications_enabled: parse_bool.("WANDERER_SYSTEM_NOTIFICATIONS_ENABLED", true),
    kill_notifications_enabled: parse_bool.("WANDERER_KILL_NOTIFICATIONS_ENABLED", true),
    character_tracking_enabled: parse_bool.("WANDERER_CHARACTER_TRACKING_ENABLED", true),
    system_tracking_enabled: parse_bool.("WANDERER_SYSTEM_TRACKING_ENABLED", true),
    status_messages_disabled: parse_bool.("WANDERER_DISABLE_STATUS_MESSAGES", false),
    track_kspace_systems: parse_bool.("WANDERER_FEATURE_TRACK_KSPACE", true)
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
