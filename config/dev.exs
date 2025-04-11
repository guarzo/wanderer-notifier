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
  backends: [:console, {LoggerFileBackend, :info_log}, {LoggerFileBackend, :kills_log}]

# Configure console logging to match file logging level and format
config :logger, :console,
  level: :info,
  format: "[$level] $message\n",
  metadata: [
    :module,
    :function,
    :trace_id,
    :character_id,
    :kill_id,
    :killmail_id,
    :system_id,
    :system_name
  ]

# Configure general debug file logging
config :logger, :info_log,
  path: "log/debug.log",
  level: :info,
  format: "$time [$level] $metadata$message\n",
  metadata: [
    :module,
    :function,
    :trace_id,
    :character_id,
    :kill_id,
    :killmail_id,
    :system_id,
    :system_name
  ]

# Make sure kill-specific file logging is also configured
config :logger, :kills_log,
  path: "log/kills_debug.log",
  level: :info,
  format: "$time [$level] $metadata$message\n",
  metadata: [
    :module,
    :function,
    :trace_id,
    :character_id,
    :kill_id,
    :killmail_id,
    :system_id,
    :system_name
  ]

# Set debug level for kill processing modules to ensure we get all the debugging information
config :logger, :module_levels, %{
  "WandererNotifier.Api.ZKill" => :warn,
  "WandererNotifier.Api.ZKill.Client" => :warn,
  "WandererNotifier.Api.ZKill.Service" => :warn,
  "WandererNotifier.Api.ZKill.Websocket" => :warn,
  "WandererNotifier.Api.Character.KillsService" => :warn,
  "WandererNotifier.KillmailProcessing.Pipeline" => :info,
  "WandererNotifier.Processing.Killmail" => :info,
  "WandererNotifier.Processing.Killmail.Persistence" => :info,
  "WandererNotifier.Debug.ProcessKillDebug" => :info,
  "WandererNotifier.Debug.PipelineDebug" => :info
}

# Configure persistence feature overrides for development
config :wanderer_notifier, :persistence,
  enabled: true,
  retention_period_days: 180,
  # Run aggregation every 5 minutes in development for testing
  aggregation_schedule: "*/5 * * * *"
