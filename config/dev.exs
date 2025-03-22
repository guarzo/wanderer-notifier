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

# Include more metadata in development logs
config :logger, :console, format: "$time [$level] $message\n"
