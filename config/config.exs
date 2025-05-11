import Config

# Set environment based on MIX_ENV at compile time
config :wanderer_notifier, env: config_env()

# Configure HTTP client
config :wanderer_notifier, http_client: WandererNotifier.HttpClient.Httpoison

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
config :wanderer_notifier, :websocket, %{
  enabled: true,
  url: "wss://zkillboard.com/websocket/",
  reconnect_delay: 5000,
  max_reconnects: 20,
  reconnect_window: 3600
}

# Configure the logger
config :logger,
  level: :info,
  format: "$time [$level] $message\n",
  backends: [:console],
  metadata: %{
    request_id: nil,
    error: nil,
    stacktrace: nil,
    status: nil,
    headers: nil,
    body: nil,
    kill_id: nil,
    system_id: nil,
    character_id: nil
  }

# Console logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: %{
    request_id: nil,
    error: nil,
    stacktrace: nil,
    status: nil,
    headers: nil,
    body: nil,
    kill_id: nil,
    system_id: nil,
    character_id: nil,
    system_name: nil,
    type: nil,
    url: nil
  },
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
  "WandererNotifier.Config.Timings" => :info,
  "WandererNotifier.ESI.Client" => :warn,
  "WandererNotifier.Map.Client" => :info,
  "WandererNotifier.Map.SystemsClient" => :info,
  "WandererNotifier.Map.CharactersClient" => :info,
  "WandererNotifier.Notifiers.Discord" => :info,
  "WandererNotifier.Application" => :info,
  "WandererNotifier.License.Service" => :info,
  "WandererNotifier.Core.Stats" => :info,
  "WandererNotifier.Data.Cache.Helpers" => :warn,
  "WandererNotifier.Data.Cache" => :warn,
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

# Configure cache
config :wanderer_notifier, cache_name: :wanderer_cache

# Configure service modules
config :wanderer_notifier,
  esi_service: WandererNotifier.ESI.Service,
  cache_impl: WandererNotifier.Cache.CachexImpl

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
