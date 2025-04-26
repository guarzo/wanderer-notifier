defmodule WandererNotifier.Config.Application do
  @moduledoc """
  Configuration module for WandererNotifier.
  Provides functions to access application configuration.
  """
  @behaviour WandererNotifier.Config.Behaviour

  alias WandererNotifier.Config.Features

  @type env :: :dev | :test | :prod
  @type startup_mode :: :minimal | :full

  require Logger

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
  Gets the list of watchers for development.
  """
  @spec get_watchers() :: [{atom(), [String.t() | {:cd, String.t()}]}]
  def get_watchers do
    get_env(:watchers, [])
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
    get_wanderer_env(:"discord_channel_#{feature}")
  end

  @impl true
  def character_tracking_enabled? do
    Features.character_tracking_enabled?()
  end

  @impl true
  def character_notifications_enabled? do
    Features.character_notifications_enabled?()
  end

  @impl true
  def system_notifications_enabled? do
    Features.system_notifications_enabled?()
  end

  @impl true
  def track_kspace_systems? do
    Features.track_kspace_systems?()
  end

  @impl true
  def get_map_config do
    get_wanderer_env(:map_config, %{})
  end

  @impl true
  def static_info_cache_ttl do
    get_wanderer_env(:static_info_cache_ttl, 3600)
  end

  @impl true
  def get_feature_status do
    %{
      system_tracking_enabled: system_notifications_enabled?(),
      character_tracking_enabled: character_tracking_enabled?(),
    }
  end

  # Private Helpers

  defp get_wanderer_env(key, default \\ nil) do
    get_env(:wanderer_notifier, key, default)
  end

end
