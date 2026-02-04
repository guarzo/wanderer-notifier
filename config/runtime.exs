import Config

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
# Helper functions for parsing environment variables
# ══════════════════════════════════════════════════════════════════════════════

defmodule RuntimeConfig do
  def get_env(key, default \\ nil) do
    System.get_env(key) || default
  end

  def get_integer(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> String.to_integer(value)
    end
  end

  def get_boolean(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  def parse_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  def parse_list(_), do: []

  def parse_numeric_id_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn id -> id != "" end)
    |> Enum.map(fn id ->
      case Integer.parse(id) do
        {num, ""} -> num
        _ -> nil
      end
    end)
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  def parse_numeric_id_list(nil), do: []
  def parse_numeric_id_list(""), do: []
  def parse_numeric_id_list(_), do: []
end

# ══════════════════════════════════════════════════════════════════════════════
# Validate required environment variables
# ══════════════════════════════════════════════════════════════════════════════

required_vars = ["DISCORD_BOT_TOKEN", "MAP_URL", "MAP_NAME", "MAP_API_KEY"]
missing_vars = Enum.filter(required_vars, &is_nil(System.get_env(&1)))

if length(missing_vars) > 0 do
  IO.puts("ERROR: Missing required environment variables: #{Enum.join(missing_vars, ", ")}")

  if config_env() == :prod do
    System.halt(1)
  end
end

# ══════════════════════════════════════════════════════════════════════════════
# Discord Configuration
# ══════════════════════════════════════════════════════════════════════════════

# Skip nostrum configuration in test environment - tests use config/test.exs settings
# and nostrum is not started as an application in test mode (see mix.exs extra_applications)
if config_env() != :test do
  config :nostrum,
    token: RuntimeConfig.get_env("DISCORD_BOT_TOKEN"),
    gateway_intents: [:guilds, :guild_messages, :guild_voice_states]
end

# Configure Gun HTTP client used by Nostrum - runtime configuration
# These settings help prevent connection timeouts and stuck connections
config :gun,
  # Top-level connection timeout (how long to wait for initial connection)
  connect_timeout: RuntimeConfig.get_integer("GUN_CONNECT_TIMEOUT", 10_000),
  # Retry configuration for failed connections
  retry: RuntimeConfig.get_integer("GUN_RETRY_COUNT", 3),
  retry_timeout: RuntimeConfig.get_integer("GUN_RETRY_TIMEOUT", 5_000),
  # Protocol selection (HTTP/1.1 only to avoid HTTP/2 issues with Discord)
  protocols: [:http],
  # HTTP-specific options
  http_opts: %{
    # Keep connections alive to avoid reconnection overhead
    keepalive: RuntimeConfig.get_integer("GUN_KEEPALIVE", 10_000),
    # HTTP version
    version: :"HTTP/1.1",
    # Closing timeout - how long to wait for graceful close
    closing_timeout: RuntimeConfig.get_integer("GUN_CLOSING_TIMEOUT", 5_000)
  },
  # TCP options for connection handling
  tcp_opts: [
    # Force IPv4 address family (avoids IPv6 issues)
    :inet,
    # TCP keepalive to detect dead connections
    keepalive: true,
    # Disable Nagle's algorithm for lower latency
    nodelay: true,
    # Send buffer size (bytes)
    sndbuf: RuntimeConfig.get_integer("GUN_SNDBUF", 65536),
    # Receive buffer size (bytes)
    recbuf: RuntimeConfig.get_integer("GUN_RECBUF", 65536)
  ],
  # Supervise connections for auto-restart on failure
  supervise: true

# ══════════════════════════════════════════════════════════════════════════════
# Main Application Configuration
# ══════════════════════════════════════════════════════════════════════════════

config :wanderer_notifier,
  # Discord settings
  discord_channel_id: RuntimeConfig.get_env("DISCORD_CHANNEL_ID"),
  discord_application_id: RuntimeConfig.get_env("DISCORD_APPLICATION_ID"),
  discord_bot_token: RuntimeConfig.get_env("DISCORD_BOT_TOKEN"),
  discord_guild_id: RuntimeConfig.get_env("DISCORD_GUILD_ID"),
  discord_system_kill_channel_id: RuntimeConfig.get_env("DISCORD_SYSTEM_KILL_CHANNEL_ID"),
  discord_character_kill_channel_id: RuntimeConfig.get_env("DISCORD_CHARACTER_KILL_CHANNEL_ID"),
  discord_system_channel_id: RuntimeConfig.get_env("DISCORD_SYSTEM_CHANNEL_ID"),
  discord_character_channel_id: RuntimeConfig.get_env("DISCORD_CHARACTER_CHANNEL_ID"),
  discord_rally_channel_id: RuntimeConfig.get_env("DISCORD_RALLY_CHANNEL_ID"),
  discord_rally_group_ids:
    RuntimeConfig.parse_numeric_id_list(
      RuntimeConfig.get_env("DISCORD_RALLY_GROUP_IDS") ||
        RuntimeConfig.get_env("DISCORD_RALLY_GROUP_ID")
    ),

  # Map settings
  map_token: RuntimeConfig.get_env("MAP_API_KEY"),
  map_api_key: RuntimeConfig.get_env("MAP_API_KEY"),
  map_url: RuntimeConfig.get_env("MAP_URL"),
  map_name: RuntimeConfig.get_env("MAP_NAME"),

  # License settings
  license_key: RuntimeConfig.get_env("LICENSE_KEY"),
  license_manager_api_url:
    RuntimeConfig.get_env("LICENSE_MANAGER_URL", "https://lm.wanderer.ltd/api"),
  api_token: RuntimeConfig.get_env("NOTIFIER_API_TOKEN"),

  # Server settings
  port: RuntimeConfig.get_integer("PORT", 4000),
  host: RuntimeConfig.get_env("HOST", "localhost"),
  scheme: RuntimeConfig.get_env("SCHEME", "http"),
  public_url: RuntimeConfig.get_env("PUBLIC_URL"),

  # WebSocket & API settings
  websocket_url: RuntimeConfig.get_env("WEBSOCKET_URL", "ws://host.docker.internal:4004"),
  wanderer_kills_base_url:
    RuntimeConfig.get_env("WANDERER_KILLS_URL", "http://host.docker.internal:4004"),
  wanderer_kills_url:
    RuntimeConfig.get_env("WANDERER_KILLS_URL", "http://host.docker.internal:4004"),

  # Janice API settings
  janice_api_token: RuntimeConfig.get_env("JANICE_API_TOKEN"),
  janice_api_url: RuntimeConfig.get_env("JANICE_API_URL", "https://janice.e-351.com"),
  notable_item_threshold: RuntimeConfig.get_integer("NOTABLE_ITEM_THRESHOLD", 50_000_000),
  notable_items_enabled: RuntimeConfig.get_boolean("NOTABLE_ITEMS_ENABLED", false),

  # Cache settings
  cache_dir: RuntimeConfig.get_env("CACHE_DIR", "/app/data/cache"),

  # Feature flags
  notifications_enabled: RuntimeConfig.get_boolean("NOTIFICATIONS_ENABLED", true),
  kill_notifications_enabled: RuntimeConfig.get_boolean("KILL_NOTIFICATIONS_ENABLED", true),
  system_notifications_enabled: RuntimeConfig.get_boolean("SYSTEM_NOTIFICATIONS_ENABLED", true),
  character_notifications_enabled:
    RuntimeConfig.get_boolean("CHARACTER_NOTIFICATIONS_ENABLED", true),
  rally_notifications_enabled: RuntimeConfig.get_boolean("RALLY_NOTIFICATIONS_ENABLED", true),
  status_messages_enabled: RuntimeConfig.get_boolean("STATUS_MESSAGES_ENABLED", false),
  priority_systems_only_enabled:
    RuntimeConfig.get_boolean("PRIORITY_SYSTEMS_ONLY_ENABLED", false),
  wormhole_only_kill_notifications_enabled:
    RuntimeConfig.get_boolean("WORMHOLE_ONLY_KILL_NOTIFICATIONS_ENABLED", false),

  # Lists
  character_exclude_list:
    RuntimeConfig.parse_list(RuntimeConfig.get_env("CHARACTER_EXCLUDE_LIST", "")),
  system_exclude_list: RuntimeConfig.parse_list(RuntimeConfig.get_env("SYSTEM_EXCLUDE_LIST", "")),
  corporation_kill_focus:
    RuntimeConfig.parse_numeric_id_list(RuntimeConfig.get_env("CORPORATION_KILL_FOCUS", "")),

  # Module configuration
  config: WandererNotifier.Shared.Config

# ══════════════════════════════════════════════════════════════════════════════
# HTTP Service Configurations
# ══════════════════════════════════════════════════════════════════════════════
# These configurations can be overridden at runtime via environment variables.
# If not set, the Http module falls back to hardcoded defaults for backward compatibility.
#
# To customize a specific service, set environment variables like:
#   HTTP_ESI_TIMEOUT=5000
#   HTTP_ESI_RETRY_COUNT=5
#
# Note: Middleware configurations use module references and are not easily
# configurable via environment variables, so they use defaults.

config :wanderer_notifier, :http_service_configs, %{
  esi: [
    # ESI typically responds in 80-240ms, 3s timeout is plenty
    timeout: RuntimeConfig.get_integer("HTTP_ESI_TIMEOUT", 3_000),
    retry_count: RuntimeConfig.get_integer("HTTP_ESI_RETRY_COUNT", 3),
    retry_delay: RuntimeConfig.get_integer("HTTP_ESI_RETRY_DELAY", 500),
    retryable_status_codes: [429, 500, 502, 503, 504],
    # Use dynamic rate limiting based on X-ESI-Error-Limit-* headers
    middlewares: [
      WandererNotifier.Infrastructure.Http.Middleware.Retry,
      WandererNotifier.Infrastructure.Http.Middleware.DynamicRateLimiter
    ],
    decode_json: true
  ],
  wanderer_kills: [
    # WandererKills is fast, 5s timeout is generous
    timeout: RuntimeConfig.get_integer("HTTP_WANDERER_KILLS_TIMEOUT", 5_000),
    retry_count: RuntimeConfig.get_integer("HTTP_WANDERER_KILLS_RETRY_COUNT", 2),
    retry_delay: RuntimeConfig.get_integer("HTTP_WANDERER_KILLS_RETRY_DELAY", 500),
    retryable_status_codes: [429, 500, 502, 503, 504],
    rate_limit: [requests_per_second: 10, burst_capacity: 20, per_host: true],
    middlewares: [
      WandererNotifier.Infrastructure.Http.Middleware.Retry,
      WandererNotifier.Infrastructure.Http.Middleware.RateLimiter
    ],
    decode_json: true
  ],
  license: [
    # License validation typically 300-400ms
    timeout: RuntimeConfig.get_integer("HTTP_LICENSE_TIMEOUT", 3_000),
    retry_count: RuntimeConfig.get_integer("HTTP_LICENSE_RETRY_COUNT", 2),
    retry_delay: RuntimeConfig.get_integer("HTTP_LICENSE_RETRY_DELAY", 1_000),
    # Don't retry auth failures
    retryable_status_codes: [500, 502, 503, 504],
    rate_limit: [requests_per_second: 1, burst_capacity: 2, per_host: true],
    middlewares: [
      WandererNotifier.Infrastructure.Http.Middleware.Retry,
      WandererNotifier.Infrastructure.Http.Middleware.RateLimiter
    ],
    decode_json: true
  ],
  janice: [
    # Janice usually responds in 500ms, but can be slow
    timeout: RuntimeConfig.get_integer("HTTP_JANICE_TIMEOUT", 5_000),
    retry_count: RuntimeConfig.get_integer("HTTP_JANICE_RETRY_COUNT", 3),
    retry_delay: RuntimeConfig.get_integer("HTTP_JANICE_RETRY_DELAY", 500),
    retryable_status_codes: [429, 500, 502, 503, 504],
    rate_limit: [requests_per_second: 5, burst_capacity: 10, per_host: true],
    middlewares: [
      WandererNotifier.Infrastructure.Http.Middleware.Retry,
      WandererNotifier.Infrastructure.Http.Middleware.RateLimiter
    ],
    decode_json: true
  ],
  map: [
    timeout: RuntimeConfig.get_integer("HTTP_MAP_TIMEOUT", 60_000),
    retry_count: RuntimeConfig.get_integer("HTTP_MAP_RETRY_COUNT", 2),
    retry_delay: RuntimeConfig.get_integer("HTTP_MAP_RETRY_DELAY", 500),
    retryable_status_codes: [500, 502, 503, 504],
    # Internal service, no rate limiting
    disable_middleware: true,
    decode_json: true
  ],
  discord: [
    # Discord API typically responds in 200-500ms, but can be slow during outages
    timeout: RuntimeConfig.get_integer("HTTP_DISCORD_TIMEOUT", 30_000),
    # Disable retries to prevent duplicate notifications
    retry_count: RuntimeConfig.get_integer("HTTP_DISCORD_RETRY_COUNT", 0),
    retryable_status_codes: [429, 500, 502, 503, 504],
    # Use dynamic rate limiting based on X-RateLimit-* headers with webhook and global limits
    middlewares: [WandererNotifier.Infrastructure.Http.Middleware.DynamicRateLimiter],
    decode_json: true
  ],
  streaming: [
    timeout: :infinity,
    stream: true,
    retry_count: 0,
    disable_middleware: true,
    follow_redirects: false,
    decode_json: false
  ],
  wanderer_sde: [
    timeout: RuntimeConfig.get_integer("HTTP_WANDERER_SDE_TIMEOUT", 60_000),
    retry_count: RuntimeConfig.get_integer("HTTP_WANDERER_SDE_RETRY_COUNT", 3),
    retry_delay: RuntimeConfig.get_integer("HTTP_WANDERER_SDE_RETRY_DELAY", 2_000),
    retryable_status_codes: [429, 500, 502, 503, 504],
    rate_limit: [
      service: :wanderer_sde,
      requests_per_second: 10,
      burst_capacity: 20,
      per_host: true
    ],
    middlewares: [
      WandererNotifier.Infrastructure.Http.Middleware.Retry,
      WandererNotifier.Infrastructure.Http.Middleware.RateLimiter
    ],
    decode_json: false
  ]
}

# ══════════════════════════════════════════════════════════════════════════════
# Phoenix Endpoint Configuration
# ══════════════════════════════════════════════════════════════════════════════

# Generate secret key base if not provided
secret_key_base =
  RuntimeConfig.get_env("SECRET_KEY_BASE") ||
    :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)

# Generate signing salt if not provided  
live_view_signing_salt =
  RuntimeConfig.get_env("LIVE_VIEW_SIGNING_SALT") ||
    :crypto.strong_rand_bytes(32) |> Base.encode64() |> binary_part(0, 32)

config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  url: [
    host: RuntimeConfig.get_env("HOST", "localhost"),
    port: RuntimeConfig.get_integer("PORT", 4000),
    scheme: RuntimeConfig.get_env("SCHEME", "http")
  ],
  http: [
    port: RuntimeConfig.get_integer("PORT", 4000),
    transport_options: [socket_opts: [:inet6]]
  ],
  # Don't start the server in test mode to avoid port conflicts
  server: config_env() != :test,
  secret_key_base: secret_key_base,
  live_view: [
    signing_salt: live_view_signing_salt
  ]

# ══════════════════════════════════════════════════════════════════════════════
# Logger Configuration
# ══════════════════════════════════════════════════════════════════════════════

# Only configure the file backend and basic settings here
# Let prod.exs handle the console logger configuration
config :logger,
  level: :info

# File logger configuration (backend is added dynamically in application.ex)
if Code.ensure_loaded?(LoggerFileBackend) do
  cache_dir = RuntimeConfig.get_env("CACHE_DIR", "/app/data/cache")

  config :logger, :file_log,
    path: Path.join([cache_dir, "logs", "wanderer_notifier.log"]),
    level: :info,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :category]
end
