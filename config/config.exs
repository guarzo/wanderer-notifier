import Config

# Set environment based on MIX_ENV at compile time
config :wanderer_notifier, env: config_env()

# Enable schedulers by default
config :wanderer_notifier,
  schedulers_enabled: true,
  features: [
    system_tracking_enabled: true,
    character_tracking_enabled: true,
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true
  ]

# Configure HTTP client
config :wanderer_notifier,
  http_client: WandererNotifier.HTTP,
  default_timeout: 5_000,
  default_recv_timeout: 5_000,
  default_connect_timeout: 3_000,
  default_pool_timeout: 3_000

# Configure Finch to use IPv4 only to avoid production IPv6 timeout issues
config :finch, :default_pool_config, [
  pool_size: 25,
  max_idle_time: 30_000,
  conn_opts: [
    timeout: 10_000,
    transport_opts: [
      inet6: false,  # Disable IPv6
      inet: true     # Force IPv4
    ]
  ]
]

# Configure MIME types
config :mime, :types, %{
  "text/html" => ["html", "htm"],
  "text/css" => ["css"],
  "application/javascript" => ["js"],
  "text/javascript" => ["mjs"],
  "application/json" => ["json"],
  "image/png" => ["png"],
  "image/jpeg" => ["jpg", "jpeg"],
  "image/svg+xml" => ["svg"]
}

# Configure MIME extensions preferences
config :mime, :extensions, %{
  "mjs" => "text/javascript"
}

# Configure Phoenix
config :wanderer_notifier, WandererNotifierWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: WandererNotifierWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WandererNotifier.PubSub,
  live_view: [],
  server: false

# Configure Phoenix PubSub
config :wanderer_notifier, WandererNotifier.PubSub, adapter: Phoenix.PubSub.PG

# Configure JSON library for Phoenix
config :phoenix, :json_library, Jason

# Configure Hammer rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2, cleanup_interval_ms: 60_000 * 10]}

# Configure the logger
config :logger,
  level: :info,
  format: "$time [$level] $message\n",
  backends: [:console]

# Console logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:pid, :module, :file, :line],
  colors: [
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  ]

# Module-specific log levels
# This allows fine-grained control over logging
config :logger, :module_levels, %{
  "WandererNotifier.Service.KillProcessor" => :info,
  "WandererNotifier.Core.Maintenance.Scheduler" => :info,
  "WandererNotifier.Config" => :info,
  "WandererNotifier.ESI.Client" => :warn,
  "WandererNotifier.Map.Client" => :info,
  "WandererNotifier.Map.SystemsClient" => :info,
  "WandererNotifier.Map.CharactersClient" => :info,
  "WandererNotifier.Notifiers.Discord" => :info,
  "WandererNotifier.Application" => :info,
  "WandererNotifier.License.Service" => :info,
  "WandererNotifier.Core.Stats" => :info,
  "WandererNotifier.Core.Application.Service" => :info,
  "WandererNotifier.Services.KillProcessor" => :debug,
  "WandererNotifier.Services.NotificationDeterminer" => :debug,
  "WandererNotifier.Supervisors.Basic" => :info,
  "WandererNotifier" => :info,
  "WandererNotifier.Cache.Helpers" => :warn,
  "WandererNotifier.Cache" => :warn
}

# Nostrum compile-time configuration
config :nostrum,
  token: "intentionally invalid for runtime config only",
  gateway_intents: [
    :guilds,
    :guild_messages
  ],
  cache_guilds: false,
  cache_users: false,
  cache_channels: false,
  caches: [],
  # Disable ffmpeg warnings since we're not using voice features
  ffmpeg: false,
  # HTTP timeout configuration
  gun_timeout: 10_000,
  gun_connect_timeout: 5_000

# Add backoff configuration to help with rate limiting
config :nostrum, :gateway,
  backoff: [
    initial: 5000,
    max: 300_000
  ]

# Configure Gun HTTP client used by Nostrum for better connection handling
config :gun,
  # Connection pool configuration
  http_opts: %{
    connect_timeout: 10_000,
    timeout: 30_000,
    retry: 3,
    retry_timeout: 5_000
  },
  # Connection handling - force IPv4 to avoid IPv6 timeout issues
  conn_opts: %{
    keepalive: :infinity,
    retry: 3,
    supervise: false,
    transport_opts: [
      inet6: false,  # Disable IPv6
      inet: true     # Force IPv4
    ]
  }

# Configure cache
config :wanderer_notifier,
  cache_name: :wanderer_cache

# Configure WebSocket and WandererKills service
config :wanderer_notifier,
  # Enable/disable WebSocket client (useful for development/testing)
  websocket_enabled: true,
  # WebSocket URL for external killmail service
  websocket_url: "ws://host.docker.internal:4004",
  # Phoenix WebSocket protocol version ("1.0.0", "2.0.0", or nil for auto-negotiate)
  phoenix_websocket_version: nil,
  # WandererKills API base URL
  wanderer_kills_base_url: "http://host.docker.internal:4004",
  # Maximum retries for WandererKills API requests
  wanderer_kills_max_retries: 3

# Configure service modules with standardized behavior implementations
config :wanderer_notifier,
  character_module: WandererNotifier.Domains.CharacterTracking.Character,
  system_module: WandererNotifier.Domains.SystemTracking.System,
  deduplication_module: WandererNotifier.Domains.Notifications.CacheImpl,
  config_module: WandererNotifier.Shared.Config

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env() |> to_string() |> String.downcase()}.exs"
