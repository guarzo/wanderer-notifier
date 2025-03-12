import Config

# Set a higher log level in development to see more details
config :logger, level: :info

# Include more metadata in development logs
config :logger, :console,
  format: "$time [$level] $message\n"
