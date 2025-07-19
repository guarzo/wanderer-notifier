defmodule WandererNotifier.Shared.Config.EnvProvider do
  @moduledoc """
  Behaviour for environment variable providers.
  This allows for dependency injection and easier testing.
  """

  @doc """
  Gets an environment variable value.
  """
  @callback get_env(String.t()) :: String.t() | nil

  @doc """
  Gets an environment variable value with a default.
  """
  @callback get_env(String.t(), String.t()) :: String.t()

  @doc """
  Fetches an environment variable value, raising if not found.
  """
  @callback fetch_env!(String.t()) :: String.t()
end
