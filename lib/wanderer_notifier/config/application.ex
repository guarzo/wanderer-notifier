defmodule WandererNotifier.Config.Application do
  @moduledoc """
  Configuration module for application-level settings.
  Handles environment, startup mode, and other application-wide configurations.
  """

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
  Gets the database configuration.
  """
  @spec get_database_config() :: Keyword.t()
  def get_database_config do
    [
      username: get_env_with_fallback("WANDERER_DB_USER", "POSTGRES_USER", "postgres"),
      password: get_env_with_fallback("WANDERER_DB_PASSWORD", "POSTGRES_PASSWORD", "postgres"),
      hostname: get_env_with_fallback("WANDERER_DB_HOST", "POSTGRES_HOST", "postgres"),
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
    {:ok, get_env(WandererNotifier.Repo, %{})}
  end

  @doc """
  Get the application configuration.
  """
  def get_app_config do
    {:ok, get_env(:app, %{})}
  end

  @doc """
  Gets a configuration value from the application environment.
  """
  def get_env(app, key, default \\ nil) do
    Application.get_env(app, key, default)
  end

  @doc """
  Puts a configuration value in the application environment.
  """
  def put_env(app, key, value) do
    Application.put_env(app, key, value)
  end

  # Private Helpers

  defp get_database_name do
    get_env_with_fallback(
      "WANDERER_DB_NAME",
      "POSTGRES_DB",
      "wanderer_notifier_#{get_env()}"
    )
  end

  defp get_database_port do
    get_env_with_fallback("WANDERER_DB_PORT", "POSTGRES_PORT", "5432")
    |> String.to_integer()
  end

  defp get_database_pool_size do
    get_env_with_fallback("WANDERER_DB_POOL_SIZE", "POSTGRES_POOL_SIZE", "10")
    |> String.to_integer()
  end

  defp get_env_with_fallback(primary, fallback, default) do
    System.get_env(primary) || System.get_env(fallback) || default
  end
end
