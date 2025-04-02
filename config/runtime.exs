import Config
import Dotenvy
import Logger

defmodule EnvironmentHelper do
  @moduledoc """
  Helper functions for environment variable handling and deprecation warnings.
  """

  # Log deprecation warnings for legacy environment variables.
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
    # Check API token exists
    if is_nil(System.get_env("WANDERER_NOTIFIER_API_TOKEN")) do
      raise "WANDERER_NOTIFIER_API_TOKEN must be provided via environment variable"
    end

    # Log deprecation warnings for legacy variables
    log_deprecation(
      "APP_VERSION",
      "compile-time version from mix.exs",
      System.get_env("APP_VERSION")
    )

    log_deprecation(
      "WANDERER_API_TOKEN",
      "WANDERER_NOTIFIER_API_TOKEN",
      System.get_env("WANDERER_API_TOKEN")
    )

    log_deprecation(
      "NOTIFIER_API_TOKEN",
      "WANDERER_NOTIFIER_API_TOKEN",
      System.get_env("NOTIFIER_API_TOKEN")
    )

    log_deprecation(
      "ENABLE_TRACK_KSPACE_SYSTEMS",
      "WANDERER_FEATURE_TRACK_KSPACE",
      System.get_env("ENABLE_TRACK_KSPACE_SYSTEMS")
    )

    log_deprecation(
      "ENABLE_KILL_CHARTS",
      "WANDERER_FEATURE_KILL_CHARTS",
      System.get_env("ENABLE_KILL_CHARTS")
    )

    log_deprecation(
      "ENABLE_MAP_CHARTS",
      "WANDERER_FEATURE_MAP_CHARTS",
      System.get_env("ENABLE_MAP_CHARTS")
    )

    log_deprecation("MAP_URL", "WANDERER_MAP_URL", System.get_env("MAP_URL"))

    log_deprecation(
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

  @doc """
  Retrieves an environment variable value using the new naming if available,
  falling back to the legacy name, and returning the default if neither exists.
  """
  def get_env(env_vars, mapping, legacy_name, default) do
    new_name = Map.get(mapping, legacy_name)

    cond do
      new_name && Map.has_key?(env_vars, new_name) ->
        Map.get(env_vars, new_name)

      Map.has_key?(env_vars, legacy_name) ->
        Map.get(env_vars, legacy_name)

      true ->
        default
    end
  end

  @doc """
  Safely parses a string into an integer, returning a default if parsing fails.
  """
  def parse_integer_env(string_value, default) when is_binary(string_value) do
    case Integer.parse(string_value) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end

  def parse_integer_env(_, default), do: default

  @doc """
  Parses a map URL with name and extracts the base URL and the name component.
  """
  def parse_map_url_with_name(map_url_with_name) do
    uri = URI.parse(map_url_with_name)
    name = uri.path |> String.trim("/") |> String.split("/") |> List.last()
    url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
    {url, name}
  end
end

env_dir_prefix = Path.expand("..", __DIR__)

# Load environment variables from files and system environment.
env_vars =
  source!([
    Path.absname(".env", env_dir_prefix),
    Path.absname(".#{config_env()}.env", env_dir_prefix),
    System.get_env()
  ])

# Ensure MIX_ENV is explicitly set.
mix_env = Map.get(env_vars, "MIX_ENV", Atom.to_string(config_env()))
System.put_env("MIX_ENV", mix_env)

# Set the runtime environment based on MIX_ENV.
runtime_env = String.to_atom(mix_env)
config :wanderer_notifier, :env, runtime_env

# Mapping from legacy to new variable names for backward compatibility.
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

# Set environment variables with both old and new names for backward compatibility.
Enum.each(legacy_to_new_mapping, fn {legacy_name, new_name} ->
  # First check if new name exists
  value = Map.get(env_vars, new_name)

  # If new name doesn't exist, try legacy name
  value = if is_nil(value), do: Map.get(env_vars, legacy_name), else: value

  if value do
    # Only set the new name
    System.put_env(new_name, value)
  end
end)

# -- Core Discord configuration --
discord_token =
  EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "DISCORD_BOT_TOKEN", nil)

trimmed_token =
  if is_binary(discord_token), do: String.trim(discord_token), else: nil

if is_nil(trimmed_token) or trimmed_token == "" do
  raise "Discord bot token environment variable is required but not set or is empty"
end

# Set the runtime token for Nostrum.
config :nostrum,
  token: trimmed_token

# -- Discord and Map Configuration --
map_url_with_name =
  EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "MAP_URL_WITH_NAME", nil)

{map_url, map_name} =
  if map_url_with_name do
    EnvironmentHelper.parse_map_url_with_name(map_url_with_name)
  else
    {"", ""}
  end

config :wanderer_notifier,
  discord_bot_token: trimmed_token,
  discord_channel_id:
    EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "DISCORD_CHANNEL_ID", nil),
  map_url: map_url,
  map_name: map_name,
  map_url_with_name: map_url_with_name,
  map_token: EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "MAP_TOKEN", nil)

# -- License Configuration --
license_key =
  EnvironmentHelper.get_env(
    env_vars,
    legacy_to_new_mapping,
    "WANDERER_LICENSE_KEY",
    EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "LICENSE_KEY", nil)
  )

# Define a function to get the license manager URL based on the environment.
get_license_manager_url = fn env ->
  case env do
    :prod ->
      "https://lm.wanderer.ltd"

    _ ->
      System.get_env("WANDERER_LICENSE_MANAGER_URL") ||
        System.get_env("LICENSE_MANAGER_API_URL") ||
        "https://lm.wanderer.ltd"
  end
end

license_manager_url = get_license_manager_url.(runtime_env)
api_token_value = System.get_env("WANDERER_NOTIFIER_API_TOKEN")

config :wanderer_notifier,
  license_key: license_key,
  notifier_api_token: api_token_value,
  license_manager_api_url: license_manager_url

# -- Feature Flag Configuration --
enable_track_kspace_systems = System.get_env("ENABLE_TRACK_KSPACE_SYSTEMS")
wanderer_feature_track_kspace = System.get_env("WANDERER_FEATURE_TRACK_KSPACE")

track_kspace_enabled =
  cond do
    enable_track_kspace_systems == "true" -> true
    enable_track_kspace_systems == "false" -> false
    wanderer_feature_track_kspace == "true" -> true
    wanderer_feature_track_kspace == "false" -> false
    true -> true
  end

kill_charts_enabled =
  case EnvironmentHelper.get_env(
         env_vars,
         legacy_to_new_mapping,
         "WANDERER_FEATURE_KILL_CHARTS",
         EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "ENABLE_KILL_CHARTS", "false")
       ) do
    "true" -> true
    _ -> false
  end

map_charts_enabled =
  case EnvironmentHelper.get_env(
         env_vars,
         legacy_to_new_mapping,
         "WANDERER_FEATURE_MAP_CHARTS",
         EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "ENABLE_MAP_CHARTS", "false")
       ) do
    "true" -> true
    _ -> false
  end

config :wanderer_notifier, :wanderer_feature_map_charts, map_charts_enabled

retention_days =
  case Integer.parse(
         EnvironmentHelper.get_env(
           env_vars,
           legacy_to_new_mapping,
           "WANDERER_PERSISTENCE_RETENTION_DAYS",
           EnvironmentHelper.get_env(
             env_vars,
             legacy_to_new_mapping,
             "PERSISTENCE_RETENTION_DAYS",
             "180"
           )
         )
       ) do
    {days, _} -> days
    :error -> 180
  end

config :wanderer_notifier, :persistence,
  enabled: kill_charts_enabled,
  retention_period_days: retention_days,
  aggregation_schedule:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_PERSISTENCE_AGGREGATION_SCHEDULE",
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "PERSISTENCE_AGGREGATION_SCHEDULE",
        "0 0 * * *"
      )
    )

features_map = %{
  notifications_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_NOTIFICATIONS_ENABLED",
      "true"
    ) == "true",
  character_notifications_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_CHARACTER_NOTIFICATIONS_ENABLED",
      "true"
    ) == "true",
  system_notifications_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_SYSTEM_NOTIFICATIONS_ENABLED",
      "true"
    ) == "true",
  kill_notifications_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_KILL_NOTIFICATIONS_ENABLED",
      "true"
    ) == "true",
  character_tracking_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_CHARACTER_TRACKING_ENABLED",
      "true"
    ) == "true",
  system_tracking_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_SYSTEM_TRACKING_ENABLED",
      "true"
    ) == "true",
  tracked_systems_notifications_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_TRACKED_SYSTEMS_NOTIFICATIONS_ENABLED",
      "true"
    ) == "true",
  tracked_characters_notifications_enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_TRACKED_CHARACTERS_NOTIFICATIONS_ENABLED",
      "true"
    ) == "true",
  kill_charts:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_FEATURE_KILL_CHARTS",
      "false"
    ) == "true",
  map_charts:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_FEATURE_MAP_CHARTS",
      "false"
    ) == "true",
  track_kspace_systems: track_kspace_enabled
}

config :wanderer_notifier, features: features_map

# -- Websocket Configuration --
config :wanderer_notifier, :websocket,
  enabled:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_WEBSOCKET_ENABLED",
      "true"
    ) == "true",
  reconnect_delay:
    String.to_integer(
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_WEBSOCKET_RECONNECT_DELAY",
        "5000"
      )
    ),
  max_reconnects:
    String.to_integer(
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_WEBSOCKET_MAX_RECONNECTS",
        "20"
      )
    ),
  reconnect_window:
    String.to_integer(
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_WEBSOCKET_RECONNECT_WINDOW",
        "3600"
      )
    )

# -- Web and Port Configuration --
web_port_value =
  if runtime_env == :prod do
    4000
  else
    web_port_str =
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_PORT",
        EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "PORT", "4000")
      )

    EnvironmentHelper.parse_integer_env(web_port_str, 4000)
  end

config :wanderer_notifier, web_port: web_port_value

config :wanderer_notifier,
       :cache_dir,
       EnvironmentHelper.get_env(
         env_vars,
         legacy_to_new_mapping,
         "WANDERER_CACHE_DIR",
         EnvironmentHelper.get_env(
           env_vars,
           legacy_to_new_mapping,
           "CACHE_DIR",
           "/app/data/cache"
         )
       )

config :wanderer_notifier,
       :public_url,
       EnvironmentHelper.get_env(
         env_vars,
         legacy_to_new_mapping,
         "WANDERER_PUBLIC_URL",
         EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "PUBLIC_URL", nil)
       )

config :wanderer_notifier,
       :host,
       EnvironmentHelper.get_env(
         env_vars,
         legacy_to_new_mapping,
         "WANDERER_HOST",
         EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "HOST", "localhost")
       )

port_value =
  if runtime_env == :prod do
    4000
  else
    port_str =
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_PORT",
        EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "PORT", "4000")
      )

    EnvironmentHelper.parse_integer_env(port_str, 4000)
  end

config :wanderer_notifier, :port, port_value

config :wanderer_notifier,
       :scheme,
       EnvironmentHelper.get_env(
         env_vars,
         legacy_to_new_mapping,
         "WANDERER_SCHEME",
         EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "SCHEME", "http")
       )

# -- Database Configuration --
config :wanderer_notifier, :database,
  username:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_USER",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_USER", "postgres")
    ),
  password:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_PASSWORD",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_PASSWORD", "postgres")
    ),
  hostname:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_HOST",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_HOST", "postgres")
    ),
  database:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_NAME",
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "POSTGRES_DB",
        "wanderer_notifier_#{config_env()}"
      )
    ),
  port:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_PORT",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_PORT", "5432")
    ),
  pool_size:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_POOL_SIZE",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_POOL_SIZE", "10")
    )

config :wanderer_notifier, WandererNotifier.Data.Repo,
  username:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_USER",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_USER", "postgres")
    ),
  password:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_PASSWORD",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_PASSWORD", "postgres")
    ),
  hostname:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_HOST",
      EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_HOST", "postgres")
    ),
  database:
    EnvironmentHelper.get_env(
      env_vars,
      legacy_to_new_mapping,
      "WANDERER_DB_NAME",
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "POSTGRES_DB",
        "wanderer_notifier_#{config_env()}"
      )
    ),
  port:
    String.to_integer(
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_DB_PORT",
        EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_PORT", "5432")
      )
    ),
  pool_size:
    String.to_integer(
      EnvironmentHelper.get_env(
        env_vars,
        legacy_to_new_mapping,
        "WANDERER_DB_POOL_SIZE",
        EnvironmentHelper.get_env(env_vars, legacy_to_new_mapping, "POSTGRES_POOL_SIZE", "10")
      )
    )

# Validate database configuration if kill charts are enabled
if kill_charts_enabled do
  Logger.info("Kill charts feature is enabled, using database configuration...")
end

EnvironmentHelper.check_env_vars()
