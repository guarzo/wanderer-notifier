import Config
import Dotenvy

env_dir_prefix = Path.expand("..", __DIR__)

# Load environment variables from files and system env
env_vars =
  source!([
    Path.absname(".env", env_dir_prefix),
    Path.absname(".#{config_env()}.env", env_dir_prefix),
    System.get_env()
  ])

# Make sure MIX_ENV is explicitly set in the system environment
mix_env = Map.get(env_vars, "MIX_ENV", Atom.to_string(config_env()))
System.put_env("MIX_ENV", mix_env)

# Set the runtime environment based on MIX_ENV
runtime_env = String.to_atom(mix_env)
config :wanderer_notifier, :env, runtime_env

# Mapping from legacy to new variable names
# This provides backward compatibility during the migration period
legacy_to_new_mapping = %{
  "DISCORD_BOT_TOKEN" => "WANDERER_DISCORD_BOT_TOKEN",
  "LICENSE_KEY" => "WANDERER_LICENSE_KEY",
  "DISCORD_CHANNEL_ID" => "WANDERER_DISCORD_CHANNEL_ID",
  "MAP_URL_WITH_NAME" => "WANDERER_MAP_URL",
  "MAP_TOKEN" => "WANDERER_MAP_TOKEN",
  "PORT" => "WANDERER_PORT",
  "HOST" => "WANDERER_HOST",
  "SCHEME" => "WANDERER_SCHEME",
  "PUBLIC_URL" => "WANDERER_PUBLIC_URL",
  "ENABLE_KILL_CHARTS" => "WANDERER_FEATURE_KILL_CHARTS",
  "ENABLE_MAP_CHARTS" => "WANDERER_FEATURE_MAP_CHARTS",
  "ENABLE_TRACK_KSPACE_SYSTEMS" => "WANDERER_FEATURE_TRACK_KSPACE",
  "FEATURE_ACTIVITY_CHARTS" => "WANDERER_FEATURE_ACTIVITY_CHARTS",
  "FEATURE_TPS_CHARTS" => "WANDERER_FEATURE_TPS_CHARTS",
  "FEATURE_MAP_TOOLS" => "WANDERER_FEATURE_MAP_TOOLS",
  "FEATURE_CORP_TOOLS" => "WANDERER_FEATURE_CORP_TOOLS",
  "DISCORD_KILL_CHANNEL_ID" => "WANDERER_DISCORD_KILL_CHANNEL_ID",
  "DISCORD_SYSTEM_CHANNEL_ID" => "WANDERER_DISCORD_SYSTEM_CHANNEL_ID",
  "DISCORD_CHARACTER_CHANNEL_ID" => "WANDERER_DISCORD_CHARACTER_CHANNEL_ID",
  "DISCORD_MAP_CHARTS_CHANNEL_ID" => "WANDERER_DISCORD_CHARTS_CHANNEL_ID",
  "POSTGRES_USER" => "WANDERER_DB_USER",
  "POSTGRES_PASSWORD" => "WANDERER_DB_PASSWORD",
  "POSTGRES_HOST" => "WANDERER_DB_HOST",
  "POSTGRES_DB" => "WANDERER_DB_NAME",
  "POSTGRES_PORT" => "WANDERER_DB_PORT",
  "POSTGRES_POOL_SIZE" => "WANDERER_DB_POOL_SIZE",
  "PERSISTENCE_RETENTION_DAYS" => "WANDERER_PERSISTENCE_RETENTION_DAYS",
  "PERSISTENCE_AGGREGATION_SCHEDULE" => "WANDERER_PERSISTENCE_AGGREGATION_SCHEDULE",
  "CACHE_DIR" => "WANDERER_CACHE_DIR",
  "NOTIFIER_API_TOKEN" => "WANDERER_NOTIFIER_API_TOKEN",
  "LICENSE_MANAGER_API_URL" => "WANDERER_LICENSE_MANAGER_URL",
  "CORP_TOOLS_API_URL" => "WANDERER_CORP_TOOLS_API_URL",
  "CORP_TOOLS_API_TOKEN" => "WANDERER_CORP_TOOLS_API_TOKEN"
}

# Helper function to get env var with new naming priority
get_env = fn legacy_name, default ->
  new_name = legacy_to_new_mapping[legacy_name]

  cond do
    # Check if new variable name is set
    new_name && Map.has_key?(env_vars, new_name) ->
      Map.get(env_vars, new_name)

    # Fall back to legacy name if available
    Map.has_key?(env_vars, legacy_name) ->
      Map.get(env_vars, legacy_name)

    # Use default if neither is available
    true ->
      default
  end
end

# Set environment variables with both old and new names for backward compatibility
Enum.each(legacy_to_new_mapping, fn {legacy_name, new_name} ->
  value = get_env.(legacy_name, nil)

  if value do
    System.put_env(legacy_name, value)
    System.put_env(new_name, value)
  end
end)

# Core Discord configuration
discord_token = get_env.("DISCORD_BOT_TOKEN", nil)
trimmed_token = if is_binary(discord_token), do: String.trim(discord_token), else: nil

if is_nil(trimmed_token) or trimmed_token == "" do
  raise "Discord bot token environment variable is required but not set or is empty"
end

# Only set the runtime token for Nostrum
config :nostrum,
  token: trimmed_token

# Discord and Map Configuration
config :wanderer_notifier,
  discord_bot_token: trimmed_token,
  discord_channel_id: get_env.("DISCORD_CHANNEL_ID", nil),
  map_url: get_env.("MAP_URL", nil),
  map_name: get_env.("MAP_NAME", nil),
  map_url_with_name: get_env.("MAP_URL_WITH_NAME", nil),
  map_token: get_env.("MAP_TOKEN", nil)

# EVE Corp Tools API Configuration
config :wanderer_notifier,
  corp_tools_api_url: get_env.("CORP_TOOLS_API_URL", nil),
  corp_tools_api_token: get_env.("CORP_TOOLS_API_TOKEN", nil)

# License Configuration
license_key = get_env.("WANDERER_LICENSE_KEY", get_env.("LICENSE_KEY", nil))

# Define a function to get the license manager URL based on environment
get_license_manager_url = fn env ->
  case env do
    :prod ->
      # In production, don't use environment variables for security
      "https://lm.wanderer.ltd"

    _ ->
      # In development, allow environment variable overrides
      System.get_env("WANDERER_LICENSE_MANAGER_URL") ||
        System.get_env("LICENSE_MANAGER_API_URL") ||
        "https://lm.wanderer.ltd"
  end
end

# Handle license manager URL differently for production vs development
license_manager_url = get_license_manager_url.(runtime_env)

# Get API token with fallback sequence
api_token_value =
  System.get_env("WANDERER_NOTIFIER_API_TOKEN") ||
    System.get_env("NOTIFIER_API_TOKEN")

config :wanderer_notifier,
  license_key: license_key,
  notifier_api_token: api_token_value,
  license_manager_api_url: license_manager_url

# In both development and production, set the API token
config :wanderer_notifier, api_token: api_token_value

# Feature flag configuration
config :wanderer_notifier,
  feature_activity_charts: get_env.("FEATURE_ACTIVITY_CHARTS", "true"),
  feature_tps_charts: get_env.("FEATURE_TPS_CHARTS", "false"),
  feature_map_tools: get_env.("FEATURE_MAP_TOOLS", "true"),
  feature_corp_tools: get_env.("FEATURE_CORP_TOOLS", "false")

# Define a function to parse integer environment variables with default value
parse_integer_env_var = fn
  string_value, default when is_binary(string_value) ->
    case Integer.parse(string_value) do
      {value, _} when value > 0 -> value
      _ -> default
    end

  _, default ->
    default
end

# Parse the web port value with safer error handling
web_port_str = get_env.("WANDERER_PORT", get_env.("PORT", "4000"))
web_port_value = parse_integer_env_var.(web_port_str, 4000)
config :wanderer_notifier, web_port: web_port_value

# Configure cache directory
config :wanderer_notifier,
       :cache_dir,
       get_env.("WANDERER_CACHE_DIR", get_env.("CACHE_DIR", "/app/data/cache"))

# Configure public URL for assets
config :wanderer_notifier,
       :public_url,
       get_env.("WANDERER_PUBLIC_URL", get_env.("PUBLIC_URL", nil))

config :wanderer_notifier, :host, get_env.("WANDERER_HOST", get_env.("HOST", "localhost"))

# Parse port with safer error handling
port_str = get_env.("WANDERER_PORT", get_env.("PORT", "4000"))
port_value = parse_integer_env_var.(port_str, 4000)
config :wanderer_notifier, :port, port_value

config :wanderer_notifier, :scheme, get_env.("WANDERER_SCHEME", get_env.("SCHEME", "http"))

# Configure kill charts feature
kill_charts_enabled =
  case get_env.("WANDERER_FEATURE_KILL_CHARTS", get_env.("ENABLE_KILL_CHARTS", "false")) do
    "true" -> true
    _ -> false
  end

# Parse retention days with safer handling
retention_days =
  case Integer.parse(
         get_env.(
           "WANDERER_PERSISTENCE_RETENTION_DAYS",
           get_env.("PERSISTENCE_RETENTION_DAYS", "180")
         )
       ) do
    {days, _} -> days
    :error -> 180
  end

config :wanderer_notifier, :persistence,
  enabled: kill_charts_enabled,
  retention_period_days: retention_days,
  # Daily at midnight
  aggregation_schedule:
    get_env.(
      "WANDERER_PERSISTENCE_AGGREGATION_SCHEDULE",
      get_env.("PERSISTENCE_AGGREGATION_SCHEDULE", "0 0 * * *")
    )

# Always configure database connection regardless of kill charts setting
config :wanderer_notifier, WandererNotifier.Repo,
  username: get_env.("WANDERER_DB_USER", get_env.("POSTGRES_USER", "postgres")),
  password: get_env.("WANDERER_DB_PASSWORD", get_env.("POSTGRES_PASSWORD", "postgres")),
  hostname: get_env.("WANDERER_DB_HOST", get_env.("POSTGRES_HOST", "postgres")),
  database:
    get_env.("WANDERER_DB_NAME", get_env.("POSTGRES_DB", "wanderer_notifier_#{config_env()}")),
  port: String.to_integer(get_env.("WANDERER_DB_PORT", get_env.("POSTGRES_PORT", "5432"))),
  pool_size:
    String.to_integer(get_env.("WANDERER_DB_POOL_SIZE", get_env.("POSTGRES_POOL_SIZE", "10")))
