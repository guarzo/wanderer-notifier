import Config

# Configure logger with standard formatting for production
config :logger,
  level: :info,
  backends: [:console, {LoggerFileBackend, :error_log}]

# Console logs with readable format
config :logger, :console,
  format: "$time [$level] [$category] $message $metadata\n",
  metadata: [:category, :trace_id, :module, :function],
  colors: [
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  ]

# Error logs with file rotation
config :logger, :error_log,
  path: "/var/log/wanderer_notifier/error.log",
  level: :error,
  format: "$time [$level] [$category] $message $metadata\n",
  metadata: [:category, :trace_id, :module, :function],
  rotate: %{max_bytes: 10_485_760, keep: 5}

# Module-specific log levels for production
# More restrictive to reduce log spam
config :logger, :module_levels, %{
  "WandererNotifier.Service.KillProcessor" => :warning,
  "WandererNotifier.Maintenance.Scheduler" => :warning,
  "WandererNotifier.Api.Map.Client" => :warning,
  "WandererNotifier.Api.Map.Systems" => :warning,
  "WandererNotifier.Api.Map.Characters" => :warning,
  "WandererNotifier.Web.Router" => :warning,
  "WandererNotifier.KillProcessor" => :warning
}

# Runtime configuration should be in runtime.exs
