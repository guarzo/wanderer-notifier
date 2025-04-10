import Config

# Set environment based on MIX_ENV at compile time
config :wanderer_notifier, env: config_env()

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

# Configure websocket defaults
config :wanderer_notifier, :websocket,
  enabled: true,
  url: "wss://zkillboard.com/websocket/",
  reconnect_delay: 5000,
  max_reconnects: 20,
  reconnect_window: 3600

# Configure the logger
config :logger,
  level: :info,
  format: "$time [$level] $message\n",
  backends: [:console, {LoggerFileBackend, :kills_log}]

# Console logger configuration
config :logger, :console,
  format: "$time [$level] $message\n",
  metadata: [:trace_id, :character_id, :kill_id],
  colors: [
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  ]

# File logger for detailed kill service debugging
config :logger, :kills_log,
  path: "log/kills_debug.log",
  level: :debug,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:module, :function, :trace_id, :character_id, :kill_id, :killmail_id, :system_id, :system_name]

# Module-specific log levels
# This allows fine-grained control over logging
config :logger, :module_levels, %{
  "WandererNotifier.Service.KillProcessor" => :info,
  "WandererNotifier.Core.Maintenance.Scheduler" => :info,
  "WandererNotifier.Config.Config" => :info,
  "WandererNotifier.Config.Timings" => :info,
  "WandererNotifier.Api.ESI.Client" => :debug,
  "WandererNotifier.Api.Map.Client" => :info,
  "WandererNotifier.Api.Map.Systems" => :info,
  "WandererNotifier.Api.Map.Characters" => :info,
  "WandererNotifier.Notifiers.Discord" => :info,
  "WandererNotifier.Api.ZKill.Websocket" => :info,
  "WandererNotifier.Application" => :info,
  "WandererNotifier.License.Service" => :info,
  "WandererNotifier.Core.Stats" => :info,
  "WandererNotifier.Data.Cache.Repository" => :info,
  "WandererNotifier.Data.Cache.Helpers" => :info,
  "WandererNotifier.Data.Cache" => :info,
  "WandererNotifier.Data.Repository" => :info,
  "WandererNotifier.Data.Repo" => :info,
  "WandererNotifier.Core.Application.Service" => :info,
  "WandererNotifier.Services.KillProcessor" => :info,
  "WandererNotifier.Services.NotificationDeterminer" => :info,
  "WandererNotifier.Supervisors.Basic" => :info,
  "WandererNotifier.Resources.KillmailPersistence" => :info,
  "WandererNotifier.Api.Character.KillsService" => :info,
  "WandererNotifier.KillmailProcessing.Pipeline" => :info,
  "WandererNotifier" => :info
}

# Nostrum compile-time configuration
config :nostrum,
  token: "intentionally invalid for runtime config only",
  gateway_intents: [],
  cache_guilds: false,
  cache_users: false,
  cache_channels: false,
  caches: [],
  # Disable ffmpeg warnings since we're not using voice features
  ffmpeg: false

# Add backoff configuration to help with rate limiting
config :nostrum, :gateway,
  backoff: [
    initial: 1000,
    max: 120_000
  ]

# Configure Ecto timestamps
config :wanderer_notifier, WandererNotifier.Data.Repo,
  migration_timestamps: [type: :utc_datetime_usec]

# Configure persistence feature defaults
config :wanderer_notifier, :persistence,
  enabled: true,
  retention_period_days: 180,
  # Daily at midnight (minute 0, hour 0, any day, any month, any day of week)
  aggregation_schedule: "0 0 * * *"

# Configure Ash APIs
config :wanderer_notifier, :ash_apis, [
  WandererNotifier.Resources.Api
]

# Configure Ash Domains
config :wanderer_notifier,
  ash_domains: [
    WandererNotifier.Resources.Api
  ]

# Configure compatible foreign key types for Ash relationships
# This must be set at compile time
config :ash, :compatible_foreign_key_types, [
  {Ash.Type.UUID, Ash.Type.Integer}
]

# Configure Ecto repositories
config :wanderer_notifier, ecto_repos: [WandererNotifier.Data.Repo]

# Configure cache
config :wanderer_notifier, cache_name: :wanderer_cache

# Configure service modules
config :wanderer_notifier,
  zkill_service: WandererNotifier.Api.ZKill.Service,
  esi_service: WandererNotifier.Api.ESI.Service,
  chart_service_dir: "/workspace/chart-service"

# Configure ESI API settings
config :wanderer_notifier, :esi,
  # Minimum delay between requests in milliseconds
  min_request_delay_ms: 500,
  # Maximum number of retries for rate limited requests
  max_retries: 5,
  # Initial backoff time in milliseconds
  initial_backoff_ms: 3000,
  # Whether to enable adaptive throttling based on request volume
  adaptive_throttling: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
