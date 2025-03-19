import Config

# Production configuration
config :logger,
  level: :info

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
