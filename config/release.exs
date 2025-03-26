import Config

# This file is used as the runtime configuration for releases
# It is similar to runtime.exs but with some modifications for production releases

# Discord Configuration
config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN")

# Discord and Map Configuration
config :wanderer_notifier,
  discord_bot_token: System.get_env("DISCORD_BOT_TOKEN"),
  discord_channel_id: System.get_env("DISCORD_CHANNEL_ID"),
  map_url_with_name: System.get_env("MAP_URL_WITH_NAME"),
  map_token: System.get_env("MAP_TOKEN"),
  discord_map_charts_channel_id: System.get_env("DISCORD_MAP_CHARTS_CHANNEL_ID")

# EVE Corp Tools API Configuration
config :wanderer_notifier,
  corp_tools_api_url: System.get_env("CORP_TOOLS_API_URL"),
  corp_tools_api_token: System.get_env("CORP_TOOLS_API_TOKEN"),
  enable_corp_tools: System.get_env("ENABLE_CORP_TOOLS", "false") == "true",
  enable_map_tools: System.get_env("ENABLE_MAP_TOOLS", "true") == "true"

# License Configuration
config :wanderer_notifier,
  license_key: System.get_env("LICENSE_KEY"),
  notifier_api_token: System.get_env("NOTIFIER_API_TOKEN"),
  license_manager_api_url: System.get_env("LICENSE_MANAGER_API_URL")

# Feature flags
config :wanderer_notifier,
  enable_charts: System.get_env("ENABLE_CHARTS", "true") == "true",
  enable_map_charts: System.get_env("ENABLE_MAP_CHARTS", "true") == "true",
  enable_kill_charts: System.get_env("ENABLE_KILL_CHARTS", "true") == "true",
  enable_character_notifications:
    System.get_env("ENABLE_CHARACTER_NOTIFICATIONS", "false") == "true",
  enable_system_notifications: System.get_env("ENABLE_SYSTEM_NOTIFICATIONS", "false") == "true",
  enable_track_kspace_systems: System.get_env("ENABLE_TRACK_KSPACE_SYSTEMS", "true") == "true",
  process_all_kills: System.get_env("PROCESS_ALL_KILLS", "true") == "true"

# Web server configuration
config :wanderer_notifier,
  web_port: String.to_integer(System.get_env("PORT", "4000"))

# Configure cache directory
config :wanderer_notifier, :cache_dir, System.get_env("CACHE_DIR", "/app/data/cache")

# Configure public URL for assets
config :wanderer_notifier, :public_url, System.get_env("PUBLIC_URL")

config :wanderer_notifier, :host, System.get_env("HOST", "localhost")
config :wanderer_notifier, :port, String.to_integer(System.get_env("PORT", "4000"))
config :wanderer_notifier, :scheme, System.get_env("SCHEME", "http")

# Database configuration
config :wanderer_notifier, WandererNotifier.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "postgres"),
  database: System.get_env("POSTGRES_DB", "wanderer_notifier_prod"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool_size: String.to_integer(System.get_env("POSTGRES_POOL_SIZE", "10"))

# Ensure the API token is available for releases
config :wanderer_notifier,
  api_token: System.get_env("NOTIFIER_API_TOKEN")
