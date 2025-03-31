defmodule WandererNotifier.Config.Database do
  @moduledoc """
  Configuration module for database settings.

  This module centralizes all database-related configuration access,
  providing a standardized interface for retrieving database settings
  and validating configuration values.
  """

  @doc """
  Returns the complete database configuration map for use with Ecto.
  """
  @spec config() :: map()
  def config do
    %{
      username: username(),
      password: password(),
      hostname: hostname(),
      database: database_name(),
      port: port(),
      pool_size: pool_size()
    }
  end

  @doc """
  Returns the database username from environment configuration.

  Prioritizes WANDERER_DB_USER over the legacy POSTGRES_USER variable.
  """
  @spec username() :: String.t()
  def username do
    get_env(:username, "postgres")
  end

  @doc """
  Returns the database password from environment configuration.

  Prioritizes WANDERER_DB_PASSWORD over the legacy POSTGRES_PASSWORD variable.
  """
  @spec password() :: String.t()
  def password do
    get_env(:password, "postgres")
  end

  @doc """
  Returns the database hostname from environment configuration.

  Prioritizes WANDERER_DB_HOST over the legacy POSTGRES_HOST variable.
  """
  @spec hostname() :: String.t()
  def hostname do
    get_env(:hostname, "postgres")
  end

  @doc """
  Returns the database name from environment configuration.

  Prioritizes WANDERER_DB_NAME over the legacy POSTGRES_DB variable.
  If neither is set, generates a name based on the current environment.
  """
  @spec database_name() :: String.t()
  def database_name do
    environment = Application.get_env(:wanderer_notifier, :env, :dev)
    get_env(:database, "wanderer_notifier_#{environment}")
  end

  @doc """
  Returns the database port from environment configuration.

  Prioritizes WANDERER_DB_PORT over the legacy POSTGRES_PORT variable.
  """
  @spec port() :: integer()
  def port do
    get_env(:port, "5432") |> String.to_integer()
  end

  @doc """
  Returns the database connection pool size from environment configuration.

  Prioritizes WANDERER_DB_POOL_SIZE over the legacy POSTGRES_POOL_SIZE variable.
  """
  @spec pool_size() :: integer()
  def pool_size do
    get_env(:pool_size, "10") |> String.to_integer()
  end

  @doc """
  Validates that all required database configuration values are present and valid.

  Returns :ok if the configuration is valid, or {:error, reason} if not.
  """
  @spec validate() :: :ok | {:error, String.t()}
  def validate do
    # For now, we're simply checking if critical parameters are non-empty
    cond do
      username() == "" -> {:error, "Database username cannot be empty"}
      password() == "" -> {:error, "Database password cannot be empty"}
      hostname() == "" -> {:error, "Database hostname cannot be empty"}
      database_name() == "" -> {:error, "Database name cannot be empty"}
      true -> :ok
    end
  end

  # Private helper function to get configuration values
  defp get_env(key, default) do
    config = Application.get_env(:wanderer_notifier, :database, %{})

    case config do
      config when is_map(config) ->
        Map.get(config, key, default)

      config when is_list(config) ->
        Keyword.get(config, key, default)

      _ ->
        default
    end
  end
end
