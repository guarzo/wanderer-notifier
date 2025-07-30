defmodule WandererNotifier.Shared.Config.MockEnvProvider do
  @moduledoc """
  Mock implementation of EnvProvider for testing.
  """

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def set_env(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  def clear_env do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  def get_env(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  def get_env(key, default) do
    Agent.get(__MODULE__, &Map.get(&1, key, default))
  end

  def fetch_env!(key) do
    case get_env(key) do
      nil -> raise ArgumentError, "Environment variable #{key} is not set"
      value -> value
    end
  end
end
