import Config

# Enable hot code reloading
config :exsync,
  reload_timeout: 150,
  reload_callback: {WandererNotifier.Application, :reload},
  extensions: [".ex", ".exs"]

# Set a higher log level in development to see more details
config :logger, level: :info

# Include more metadata in development logs
config :logger, :console,
  format: "$time [$level] $message\n"
