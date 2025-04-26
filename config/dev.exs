import Config

# Enable hot code reloading
config :exsync,
  reload_timeout: 150,
  reload_callback: {WandererNotifier.Application, :reload},
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
  metadata: [:trace_id]

# Configure file logging
config :logger, :debug_log,
  path: "log/debug.log",
  level: :debug,
  format: "$time [$level] $metadata$message\n",
  metadata: [:trace_id, :character_id, :kill_count, :killmail_id]

# Set ZKill-specific logs to info level
config :logger, :module_levels, %{
  "WandererNotifier.Api.ZKill" => :info,
  "WandererNotifier.Api.ZKill.Client" => :info,
  "WandererNotifier.Api.ZKill.Service" => :info,
  "WandererNotifier.Api.ZKill.Websocket" => :info
}
