import Config

# Set environment based on MIX_ENV at compile time
config :wanderer_notifier, env: config_env()

# Configure MIME types
config :mime, :types, %{
  "text/html" => ["html", "htm"],
  "text/css" => ["css"],
  "application/javascript" => ["js"],
  "text/javascript" => ["mjs"],
  "application/json" => ["json"],
  "image/png" => ["png"],
  "image/jpeg" => ["jpg", "jpeg"],
  "image/svg+xml" => ["svg"]
}

# Configure MIME extensions preferences
config :mime, :extensions, %{
  "mjs" => "text/javascript"
}

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

# Nostrum compile-time configuration
config :nostrum,
  gateway_intents: [:guilds, :guild_messages],
  num_shards: :auto,
  request_guild_members: false,
  caches: [
    :guilds,  # Required cache
    :guild_channels  # Required cache
  ]

# Add backoff configuration to help with rate limiting
config :nostrum, :gateway,
  backoff: [
    initial: 1000,
    max: 120_000
  ]

# Configure cache directory
config :wanderer_notifier, :cache_dir, System.get_env("CACHE_DIR", "/app/data/cache")

# Configure public URL for assets
config :wanderer_notifier, :public_url, System.get_env("PUBLIC_URL")
config :wanderer_notifier, :host, System.get_env("HOST", "localhost")
config :wanderer_notifier, :port, String.to_integer(System.get_env("PORT", "4000"))
config :wanderer_notifier, :scheme, System.get_env("SCHEME", "http")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
