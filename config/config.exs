import Config

# Configure the logger
config :logger,
  level: :info,
  format: "$time [$level] $message\n",
  backends: [:console]

# Console logger configuration
config :logger, :console,
  format: "$time [$level] $message\n",
  colors: [
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
