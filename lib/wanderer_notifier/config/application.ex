defmodule WandererNotifier.Config.Application do
  @moduledoc """
  Configuration module for WandererNotifier.
  Provides functions to access application configuration.
  """
  @behaviour WandererNotifier.Config.Behaviour

  alias WandererNotifier.Config.Config

  @type env :: :dev | :test | :prod
  @type startup_mode :: :minimal | :full

  require Logger

  # Map of environment variable names to standardized keys
  @env_var_mapping %{
    db_username: ["WANDERER_DB_USER", "POSTGRES_USER"],
    db_password: ["WANDERER_DB_PASSWORD", "POSTGRES_PASSWORD"],
    db_hostname: ["WANDERER_DB_HOST", "POSTGRES_HOST"],
    db_name: ["WANDERER_DB_NAME", "POSTGRES_DB"],
    db_port: ["WANDERER_DB_PORT", "POSTGRES_PORT"],
    db_pool_size: ["WANDERER_DB_POOL_SIZE", "POSTGRES_POOL_SIZE"]
  }

  # Default values for configuration
  @defaults %{
    db_username: "postgres",
    db_password: "postgres",
    db_hostname: "postgres",
    db_port: "5432",
    db_pool_size: "10"
  }

  @doc """
  Gets the application environment.
  Checks environment variables and application config, defaulting to :prod.
  """
  @spec get_env() :: env()
  def get_env do
    Application.get_env(:wanderer_notifier, :env, :dev)
  end

  @doc """
  Gets the startup mode.
  Returns :minimal for test mode, :full otherwise.
  """
  @spec get_startup_mode() :: startup_mode()
  def get_startup_mode do
    if get_env(:minimal_test_mode, false), do: :minimal, else: :full
  end

  @doc """
  Gets the database configuration.
  """
  @spec get_database_config() :: Keyword.t()
  def get_database_config do
    [
      username: get_config_value(:db_username),
      password: get_config_value(:db_password),
      hostname: get_config_value(:db_hostname),
      database: get_database_name(),
      port: get_database_port(),
      pool_size: get_database_pool_size()
    ]
  end

  @doc """
  Gets the list of watchers for development.
  """
  @spec get_watchers() :: [{atom(), [String.t() | {:cd, String.t()}]}]
  def get_watchers do
    get_env(:watchers, [])
  end

  @doc """
  Get the repository configuration.
  """
  def get_repo_config do
    {:ok, get_env(WandererNotifier.Data.Repo, %{})}
  end

  @doc """
  Get the application configuration.
  """
  def get_app_config do
    {:ok, get_env(:app, %{})}
  end

  @impl true
  def get_env(app, key, default \\ nil) do
    Application.get_env(app, key, default)
  end

  @doc """
  Puts a configuration value in the application environment.
  """
  def put_env(app, key, value) do
    Application.put_env(app, key, value)
  end

  @doc """
  Validates that all application configuration values are valid.

  Returns :ok if the configuration is valid, or {:error, reason} if not.
  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    # Application configuration doesn't require extensive validation
    :ok
  end

  @impl true
  def map_url do
    get_wanderer_env(:map_url)
  end

  @impl true
  def map_token do
    get_wanderer_env(:map_token)
  end

  @impl true
  def map_csrf_token do
    get_wanderer_env(:map_csrf_token)
  end

  @impl true
  def map_name do
    get_wanderer_env(:map_name)
  end

  @impl true
  def notifier_api_token do
    get_wanderer_env(:notifier_api_token)
  end

  @impl true
  def license_key do
    get_wanderer_env(:license_key)
  end

  @impl true
  def license_manager_api_url do
    get_wanderer_env(:license_manager_api_url)
  end

  @impl true
  def license_manager_api_key do
    get_wanderer_env(:license_manager_api_key)
  end

  @impl true
  def discord_channel_id_for(feature) do
    Config.discord_channel_id_for(feature)
  end

  @impl true
  def discord_channel_id_for_activity_charts do
    Config.discord_channel_id_for_activity_charts()
  end

  @impl true
  def kill_charts_enabled? do
    Config.kill_charts_enabled?()
  end

  @impl true
  def map_charts_enabled? do
    Config.map_charts_enabled?()
  end

  @impl true
  def character_tracking_enabled? do
    Config.character_tracking_enabled?()
  end

  @impl true
  def character_notifications_enabled? do
    Config.character_notifications_enabled?()
  end

  @impl true
  def system_notifications_enabled? do
    Config.system_notifications_enabled?()
  end

  @impl true
  def track_kspace_systems? do
    Config.track_kspace_systems?()
  end

  @impl true
  def get_map_config do
    Config.get_map_config()
  end

  @impl true
  def static_info_cache_ttl do
    Config.static_info_cache_ttl()
  end

  @impl true
  def kill_notifications_enabled? do
    Config.kill_notifications_enabled?()
  end

  @impl true
  def get_feature_status do
    Config.get_feature_status()
  end

  # Private Helpers

  defp get_wanderer_env(key, default \\ nil) do
    get_env(:wanderer_notifier, key, default)
  end

  defp get_database_name do
    # Special case for database name that includes environment
    db_name = get_config_value(:db_name)

    if db_name == @defaults[:db_name] do
      "wanderer_notifier_#{get_env()}"
    else
      db_name
    end
  end

  defp get_database_port do
    get_config_value(:db_port) |> String.to_integer()
  end

  defp get_database_pool_size do
    get_config_value(:db_pool_size) |> String.to_integer()
  end

  # Get a configuration value with standardized access pattern
  defp get_config_value(key) do
    # First check Application config
    app_value = Application.get_env(:wanderer_notifier, key)

    if is_nil(app_value) do
      # If not in application config, try environment variables
      env_vars = Map.get(@env_var_mapping, key, [])

      # Try each environment variable in order
      env_value = Enum.find_value(env_vars, fn var -> System.get_env(var) end)

      # Return env value or default
      env_value || Map.get(@defaults, key)
    else
      app_value
    end
  end
end
