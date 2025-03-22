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

# Configure the logger
config :logger,
  level: :info,
  format: "$time [$level] $message\n",
  backends: [:console]

# Console logger configuration
config :logger, :console,
  format: "$time [$level] $message\n",
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
  "WandererNotifier.Maintenance.Scheduler" => :info,
  "WandererNotifier.Config" => :info,
  "WandererNotifier.Config.Timings" => :info,
  "WandererNotifier.Api.Map.Client" => :info,
  "WandererNotifier.Api.Map.Systems" => :info,
  "WandererNotifier.Api.Map.Characters" => :info,
  "WandererNotifier.Notifiers.Discord" => :info,
  "WandererNotifier.Api.ZKill.Websocket" => :info,
  "WandererNotifier.KillProcessor" => :info
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
config :wanderer_notifier, WandererNotifier.Repo, migration_timestamps: [type: :utc_datetime_usec]

# Configure persistence feature defaults
config :wanderer_notifier, :persistence,
  enabled: false,
  retention_period_days: 180,
  # Daily at midnight
  aggregation_schedule: "0 0 * * *"

# Configure Ash APIs
config :wanderer_notifier, :ash_apis, [
  WandererNotifier.Resources.Api
]

# Configure compatible foreign key types for Ash relationships
config :ash, :compatible_foreign_key_types, [
  {Ash.Type.UUID, Ash.Type.Integer}
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
