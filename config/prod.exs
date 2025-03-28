import Config

# Configure logger with basic settings - using string keys for metadata
config :logger,
  level: :info,
  format: "$time [$level] $message $metadata\n",
  metadata: [],
  backends: [:console]

# Console logger configuration
config :logger, :console,
  format: "$time [$level] $message $metadata\n",
  metadata: [],
  colors: [
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  ]

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
