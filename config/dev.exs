import Config

# Enable hot code reloading
config :exsync,
  reload_timeout: 150,
  extensions: [".ex", ".exs"]

# Configure watchers for automatic frontend asset building
config :wanderer_notifier,
  watchers: [
    npm: ["run", "watch", cd: Path.expand("../renderer", __DIR__)]
  ]

# Set a higher log level in development to see more details
config :logger, level: :info

# Configure both console and file logging
config :logger,
  backends: [:console, {LoggerFileBackend, :debug_log}]

# Include more metadata in development logs
config :logger, :console,
  format: "$time [$level] $message\n",
  metadata: [
    :trace_id,
    # WebSocket connection metadata for development debugging
    :url,
    :socket_url,
    :connection_id,
    :attempt,
    :delay_ms,
    # System and character tracking for development
    :system_id,
    :killmail_id,
    :systems_count,
    :characters_count,
    # Error context for debugging
    :error,
    :reason,
    :result,
    :event,
    :topic,
    # Performance metrics for development analysis
    :message_size,
    :uptime_seconds,
    :count,
    # Additional development debugging keys
    :systems_changed,
    :characters_changed,
    :preload
  ]

# Configure file logging
config :logger, :debug_log,
  path: "log/debug.log",
  level: :debug,
  format: "$time [$level] $metadata$message\n",
  metadata: [
    :trace_id,
    :character_id,
    :kill_count,
    :killmail_id,
    # WebSocket structured logging metadata for file output
    :url,
    :socket_url,
    :connection_id,
    :attempt,
    :delay_ms,
    :system_id,
    :systems_count,
    :characters_count,
    :error,
    :reason,
    :result,
    :event,
    :topic,
    :message_size,
    :uptime_seconds,
    :count,
    :systems_changed,
    :characters_changed,
    :preload,
    # Additional file logging metadata
    :total_systems,
    :total_characters,
    :limited_systems,
    :limited_characters
  ]

# Set ZKill-specific logs to info level
config :logger,
       :module_levels,
       %{}

# Enable system tracking by default in dev
config :wanderer_notifier, :features, system_tracking_enabled: true
