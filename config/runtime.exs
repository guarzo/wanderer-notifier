import Config
import Dotenvy

# Add a helper function to log deprecation warnings
defmodule EnvironmentHelper do
  def log_deprecation(old_var, new_var, value) when not is_nil(value) do
    IO.puts(
      IO.ANSI.yellow() <>
        IO.ANSI.bright() <>
        "[DEPRECATION WARNING] " <>
        IO.ANSI.reset() <>
        "Environment variable #{old_var} is deprecated and will be removed in a future release. " <>
        "Please use #{new_var} instead."
    )
  end

  def log_deprecation(_old_var, _new_var, _value), do: :ok

  def check_env_vars do
    # Log deprecation warnings for legacy variables
    EnvironmentHelper.log_deprecation(
      "APP_VERSION",
      "compile-time version from mix.exs",
      System.get_env("APP_VERSION")
    )

    EnvironmentHelper.log_deprecation(
      "NOTIFIER_API_TOKEN",
      "WANDERER_NOTIFIER_API_TOKEN",
      System.get_env("NOTIFIER_API_TOKEN")
    )

    EnvironmentHelper.log_deprecation(
      "ENABLE_TRACK_KSPACE_SYSTEMS",
      "WANDERER_FEATURE_TRACK_KSPACE",
      System.get_env("ENABLE_TRACK_KSPACE_SYSTEMS")
    )

    EnvironmentHelper.log_deprecation(
      "ENABLE_KILL_CHARTS",
      "WANDERER_FEATURE_KILL_CHARTS",
      System.get_env("ENABLE_KILL_CHARTS")
    )

    EnvironmentHelper.log_deprecation(
      "ENABLE_MAP_CHARTS",
      "WANDERER_FEATURE_MAP_CHARTS",
      System.get_env("ENABLE_MAP_CHARTS")
    )

    EnvironmentHelper.log_deprecation("MAP_URL", "WANDERER_MAP_URL", System.get_env("MAP_URL"))

    EnvironmentHelper.log_deprecation(
      "MAP_TOKEN",
      "WANDERER_MAP_TOKEN",
      System.get_env("MAP_TOKEN")
    )

    # Log complete removal for websocket URL
    if System.get_env("WANDERER_WEBSOCKET_URL") do
      IO.puts([
        :yellow,
        :bright,
        "[CONFIGURATION NOTICE] ",
        :reset,
        "Environment variable WANDERER_WEBSOCKET_URL is no longer used. ",
        "The websocket URL is now fixed to wss://zkillboard.com/websocket/."
      ])
    end
  end
end

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
  "FEATURE_MAP_TOOLS" => "WANDERER_FEATURE_MAP_TOOLS",
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
  "LICENSE_MANAGER_API_URL" => "WANDERER_LICENSE_MANAGER_URL"
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
map_url_with_name = get_env.("MAP_URL_WITH_NAME", nil)

# Parse map_url_with_name to extract map_url and map_name
{map_url, map_name} =
  if map_url_with_name do
    # Parse the URL properly
    uri = URI.parse(map_url_with_name)
    name = uri.path |> String.trim("/") |> String.split("/") |> List.last()
    url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
    {url, name}
  else
    {"", ""}
  end

config :wanderer_notifier,
  discord_bot_token: trimmed_token,
  discord_channel_id: get_env.("DISCORD_CHANNEL_ID", nil),
  map_url: map_url,
  map_name: map_name,
  map_url_with_name: map_url_with_name,
  map_token: get_env.("MAP_TOKEN", nil)

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

# Get API token with fallback sequence - only for non-prod environments
api_token_value =
  if runtime_env == :prod do
    # In production, don't use environment variables for security
    # This will use the baked-in value from release configuration
    nil
  else
    # In development/test, allow environment variable configuration
    System.get_env("WANDERER_NOTIFIER_API_TOKEN") ||
      System.get_env("NOTIFIER_API_TOKEN")
  end

# Configure the API token
config :wanderer_notifier,
  license_key: license_key,
  notifier_api_token: api_token_value,
  license_manager_api_url: license_manager_url

# Set the API token configuration
config :wanderer_notifier, api_token: api_token_value

# Log a warning if using legacy API token name in non-prod environments
if runtime_env != :prod do
  EnvironmentHelper.log_deprecation(
    "NOTIFIER_API_TOKEN",
    "WANDERER_NOTIFIER_API_TOKEN",
    System.get_env("NOTIFIER_API_TOKEN")
  )
end

# Feature flag configuration

# Handle ENABLE_TRACK_KSPACE_SYSTEMS first
enable_track_kspace_systems = System.get_env("ENABLE_TRACK_KSPACE_SYSTEMS")
# Handle WANDERER_FEATURE_TRACK_KSPACE as fallback
wanderer_feature_track_kspace = System.get_env("WANDERER_FEATURE_TRACK_KSPACE")

# Determine the final value - prioritize direct environment variables
track_kspace_enabled =
  cond do
    enable_track_kspace_systems == "true" -> true
    enable_track_kspace_systems == "false" -> false
    wanderer_feature_track_kspace == "true" -> true
    wanderer_feature_track_kspace == "false" -> false
    # Default to true if neither is explicitly set
    true -> true
  end

# Configure kill charts feature
kill_charts_enabled =
  case get_env.("WANDERER_FEATURE_KILL_CHARTS", get_env.("ENABLE_KILL_CHARTS", "false")) do
    "true" -> true
    _ -> false
  end

# Configure map charts feature
map_charts_enabled =
  case get_env.("WANDERER_FEATURE_MAP_CHARTS", get_env.("ENABLE_MAP_CHARTS", "false")) do
    "true" -> true
    _ -> false
  end

# Log the feature configuration for debugging
IO.puts("Feature Configuration:")
IO.puts("  Kill Charts: #{kill_charts_enabled}")
IO.puts("  Map Charts: #{map_charts_enabled}")

config :wanderer_notifier, :wanderer_feature_map_charts, map_charts_enabled

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

# Configure persistence settings
config :wanderer_notifier, :persistence,
  enabled: kill_charts_enabled,
  retention_period_days: retention_days,
  # Daily at midnight
  aggregation_schedule:
    get_env.(
      "WANDERER_PERSISTENCE_AGGREGATION_SCHEDULE",
      get_env.("PERSISTENCE_AGGREGATION_SCHEDULE", "0 0 * * *")
    )

# Update the features map to be consistent with individual settings
features_map = %{
  notifications_enabled: get_env.("WANDERER_NOTIFICATIONS_ENABLED", "true") == "true",
  character_notifications_enabled:
    get_env.("WANDERER_CHARACTER_NOTIFICATIONS_ENABLED", "true") == "true",
  system_notifications_enabled:
    get_env.("WANDERER_SYSTEM_NOTIFICATIONS_ENABLED", "true") == "true",
  kill_notifications_enabled: get_env.("WANDERER_KILL_NOTIFICATIONS_ENABLED", "true") == "true",
  character_tracking_enabled: get_env.("WANDERER_CHARACTER_TRACKING_ENABLED", "true") == "true",
  system_tracking_enabled: get_env.("WANDERER_SYSTEM_TRACKING_ENABLED", "true") == "true",
  tracked_systems_notifications_enabled:
    get_env.("WANDERER_TRACKED_SYSTEMS_NOTIFICATIONS_ENABLED", "true") == "true",
  tracked_characters_notifications_enabled:
    get_env.("WANDERER_TRACKED_CHARACTERS_NOTIFICATIONS_ENABLED", "true") == "true",
  # Use the same value we configured above
  kill_charts: get_env.("WANDERER_FEATURE_KILL_CHARTS", "false") == "true",
  # Use the same value we configured above
  map_charts: get_env.("WANDERER_FEATURE_MAP_CHARTS", "false") == "true",
  track_kspace_systems: track_kspace_enabled
}

config :wanderer_notifier, features: features_map

# Websocket Configuration - URL is fixed and not configurable via environment
config :wanderer_notifier, :websocket,
  enabled: get_env.("WANDERER_WEBSOCKET_ENABLED", "true") == "true",
  # The URL is fixed in WandererNotifier.Config.Websocket and not configurable here
  reconnect_delay: String.to_integer(get_env.("WANDERER_WEBSOCKET_RECONNECT_DELAY", "5000")),
  max_reconnects: String.to_integer(get_env.("WANDERER_WEBSOCKET_MAX_RECONNECTS", "20")),
  reconnect_window: String.to_integer(get_env.("WANDERER_WEBSOCKET_RECONNECT_WINDOW", "3600"))

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
web_port_value =
  if runtime_env == :prod do
    # Fixed port for production
    4000
  else
    web_port_str = get_env.("WANDERER_PORT", get_env.("PORT", "4000"))
    parse_integer_env_var.(web_port_str, 4000)
  end

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
port_value =
  if runtime_env == :prod do
    # Fixed port for production
    4000
  else
    port_str = get_env.("WANDERER_PORT", get_env.("PORT", "4000"))
    parse_integer_env_var.(port_str, 4000)
  end

config :wanderer_notifier, :port, port_value

config :wanderer_notifier, :scheme, get_env.("WANDERER_SCHEME", get_env.("SCHEME", "http"))

# Configure database settings
# Store database configuration in the standardized format for WandererNotifier.Config.Database
config :wanderer_notifier, :database,
  username: get_env.("WANDERER_DB_USER", get_env.("POSTGRES_USER", "postgres")),
  password: get_env.("WANDERER_DB_PASSWORD", get_env.("POSTGRES_PASSWORD", "postgres")),
  hostname: get_env.("WANDERER_DB_HOST", get_env.("POSTGRES_HOST", "postgres")),
  database:
    get_env.("WANDERER_DB_NAME", get_env.("POSTGRES_DB", "wanderer_notifier_#{config_env()}")),
  port: get_env.("WANDERER_DB_PORT", get_env.("POSTGRES_PORT", "5432")),
  pool_size: get_env.("WANDERER_DB_POOL_SIZE", get_env.("POSTGRES_POOL_SIZE", "10"))

# Configure Repo with the values from our standardized database configuration
# This maintains backward compatibility while we transition to the new approach
config :wanderer_notifier, WandererNotifier.Data.Repo,
  username: get_env.("WANDERER_DB_USER", get_env.("POSTGRES_USER", "postgres")),
  password: get_env.("WANDERER_DB_PASSWORD", get_env.("POSTGRES_PASSWORD", "postgres")),
  hostname: get_env.("WANDERER_DB_HOST", get_env.("POSTGRES_HOST", "postgres")),
  database:
    get_env.("WANDERER_DB_NAME", get_env.("POSTGRES_DB", "wanderer_notifier_#{config_env()}")),
  port: String.to_integer(get_env.("WANDERER_DB_PORT", get_env.("POSTGRES_PORT", "5432"))),
  pool_size:
    String.to_integer(get_env.("WANDERER_DB_POOL_SIZE", get_env.("POSTGRES_POOL_SIZE", "10")))

# Add call to check environment variables at the end of the file
EnvironmentHelper.check_env_vars()
