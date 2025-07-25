import Config
alias WandererNotifier.Shared.Config.EnvConfig

# ══════════════════════════════════════════════════════════════════════════════
# Environment Variable Loading (.env file support)
# ══════════════════════════════════════════════════════════════════════════════

# Load environment variables from .env file if it exists
import Dotenvy

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

# Set .env variables only if they aren't already present
Enum.each(env_vars, fn {k, v} ->
  case System.get_env(k) do
    nil -> System.put_env(k, v)
    _ -> :ok
  end
end)

# ══════════════════════════════════════════════════════════════════════════════
# Centralized Configuration (using EnvConfig)
# ══════════════════════════════════════════════════════════════════════════════

# Get all parsed environment configuration
env_config = EnvConfig.get_all_config()

# Validate required environment variables
case EnvConfig.validate_required() do
  [] ->
    :ok

  errors ->
    missing_vars = Enum.map(errors, fn {:error, _key, env_name} -> env_name end)
    IO.puts("ERROR: Missing required environment variables: #{Enum.join(missing_vars, ", ")}")
    # Don't exit in development, just warn
end

# ══════════════════════════════════════════════════════════════════════════════
# Discord Configuration
# ══════════════════════════════════════════════════════════════════════════════

config :nostrum,
  token: env_config.discord_bot_token,
  gateway_intents: [:guilds, :guild_messages]

# ══════════════════════════════════════════════════════════════════════════════
# Main Application Configuration
# ══════════════════════════════════════════════════════════════════════════════

config :wanderer_notifier,
  # Discord settings
  discord_channel_id: env_config.discord_channel_id,
  discord_application_id: env_config.discord_application_id,
  discord_bot_token: env_config.discord_bot_token,
  discord_system_kill_channel_id: env_config.discord_system_kill_channel_id,
  discord_character_kill_channel_id: env_config.discord_character_kill_channel_id,
  discord_system_channel_id: env_config.discord_system_channel_id,
  discord_character_channel_id: env_config.discord_character_channel_id,

  # Map settings
  map_token: env_config.map_api_key,
  map_url: env_config.map_url,
  map_name: env_config.map_name,

  # License settings
  license_key: env_config.license_key,
  license_manager_api_url: env_config.license_manager_url,

  # Server settings
  port: env_config.port,
  host: env_config.host,
  scheme: env_config.scheme,
  public_url: env_config.public_url,

  # WebSocket & API settings
  websocket_url: env_config.websocket_url,
  wanderer_kills_base_url: env_config.wanderer_kills_url,

  # Cache settings
  cache_dir: env_config.cache_dir,

  # Feature flags
  notifications_enabled: env_config.notifications_enabled,
  kill_notifications_enabled: env_config.kill_notifications_enabled,
  system_notifications_enabled: env_config.system_notifications_enabled,
  character_notifications_enabled: env_config.character_notifications_enabled,
  status_messages_enabled: env_config.status_messages_enabled,
  priority_systems_only: env_config.priority_systems_only,

  # Lists
  character_exclude_list: env_config.character_exclude_list,
  system_exclude_list: env_config.system_exclude_list,

  # Scheduler intervals (from constants)
  system_update_scheduler_interval:
    WandererNotifier.Shared.Types.Constants.system_update_interval(),
  character_update_scheduler_interval:
    WandererNotifier.Shared.Types.Constants.character_update_interval(),

  # Module configuration
  config: WandererNotifier.Shared.Config

# ══════════════════════════════════════════════════════════════════════════════
# Phoenix Endpoint Configuration
# ══════════════════════════════════════════════════════════════════════════════

config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  url: [
    host: env_config.host,
    port: env_config.port,
    scheme: env_config.scheme
  ],
  http: [
    port: env_config.port,
    transport_options: [socket_opts: [:inet6]]
  ],
  server: true,
  secret_key_base: env_config.secret_key_base,
  live_view: [
    signing_salt: env_config.live_view_signing_salt
  ]

# ══════════════════════════════════════════════════════════════════════════════
# Logger Configuration
# ══════════════════════════════════════════════════════════════════════════════

config :logger,
  level: :info,
  backends: [:console, {LoggerFileBackend, :file_log}]

config :logger, :file_log,
  path: Path.join([env_config.cache_dir, "logs", "wanderer_notifier.log"]),
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :category, :module, :function, :line]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :category]
