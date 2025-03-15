import Config

# Production configuration
config :logger,
  level: :info

# Module-specific log levels for production
# More restrictive to reduce log spam
config :logger, :module_levels, %{
  "WandererNotifier.Service.KillProcessor" => :warning,
  "WandererNotifier.Maintenance.Scheduler" => :warning,
  "WandererNotifier.Map.Client" => :warning,
  "WandererNotifier.Map.Systems" => :warning,
  "WandererNotifier.Map.Characters" => :warning
}

# Runtime configuration should be in runtime.exs
