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
  "WandererNotifier.Core.Maintenance.Scheduler" => :warning,
  "WandererNotifier.Config.Config" => :info,
  "WandererNotifier.Config.Timings" => :info,
  "WandererNotifier.Map.Client" => :warn,
  "WandererNotifier.Map.SystemsClient" => :warn,
  "WandererNotifier.Map.CharactersClient" => :warn,
  "WandererNotifier.Notifiers.Discord" => :warn
}

# Configure API token at compile time to prevent runtime override
config :wanderer_notifier,
  api_token: System.get_env("NOTIFIER_API_TOKEN") || "missing_token"

# Runtime configuration should be in runtime.exs
