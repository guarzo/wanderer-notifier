defmodule WandererNotifier.Config.SystemEnvProvider do
  @moduledoc """
  Default implementation of EnvProvider that uses System.get_env/1
  """

  @behaviour WandererNotifier.Config.EnvProvider

  @impl true
  def get_env(key) do
    System.get_env(key)
  end

  @impl true
  def get_env(key, default) do
    System.get_env(key, default)
  end

  @impl true
  def fetch_env!(key) do
    case System.get_env(key) do
      nil -> raise ArgumentError, "Environment variable #{key} is not set"
      value -> value
    end
  end
end
