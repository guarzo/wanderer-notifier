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
  "WandererNotifier.Services.KillProcessor" => :warning,
  "WandererNotifier.Services.Maintenance.Scheduler" => :warning,
  "WandererNotifier.Config.Config" => :info,
  "WandererNotifier.Config.Timings" => :info,
  "WandererNotifier.Api.Map.Client" => :warn,
  "WandererNotifier.Api.Map.Systems" => :warn,
  "WandererNotifier.Api.Map.Characters" => :warn,
  "WandererNotifier.Notifiers.Discord" => :warn,
  "WandererNotifier.Api.ZKill.Websocket" => :warning
}

# Runtime configuration should be in runtime.exs
