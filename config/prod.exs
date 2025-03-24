import Config

# Configure logger with JSON formatting for production
config :logger,
  level: :info,
  backends: [:console, {LoggerFileBackend, :error_log}]

# Console logs as JSON for easier parsing by log management systems
config :logger, :console,
  format: {WandererNotifier.Logger.JsonFormatter, :format},
  metadata: [:category, :trace_id, :module, :function]

# Error logs with file rotation
config :logger, :error_log,
  path: "/var/log/wanderer_notifier/error.log",
  level: :error,
  format: {WandererNotifier.Logger.JsonFormatter, :format},
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
