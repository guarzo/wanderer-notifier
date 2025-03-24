import Config

# Configure logger for production with minimal dependencies
# Disable automatic Logger starts to prevent conflicts during startup phases
config :logger,
  handle_otp_reports: false,
  handle_sasl_reports: false,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ],
  utc_log: true,
  level: :info,
  backends: [:console]

# Add file backend configuration but don't start it immediately
# This allows the application to properly initialize Logger during boot
config :logger, :console,
  format: "$time [$level] [$category] $message $metadata\n",
  metadata: [:category, :trace_id, :module, :function],
  colors: [
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  ]

# Config file logger that will be started by application code
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

# Setup LoggerFileBackend explicitly
config :logger_file_backend,
  path: "/var/log/wanderer_notifier/error.log",
  level: :error,
  format: "$time [$level] [$category] $message $metadata\n",
  metadata: [:category, :trace_id, :module, :function]

# Runtime configuration should be in runtime.exs
