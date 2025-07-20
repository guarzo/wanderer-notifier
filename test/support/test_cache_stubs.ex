defmodule WandererNotifier.Test.Support.TestCacheStubs do
  @moduledoc """
  Test stubs for cache behaviour.
  """

  def get(_key, _opts \\ []), do: {:ok, nil}

  def set(_key, value, _ttl), do: {:ok, value}

  def put(_key, value), do: {:ok, value}

  def delete(_key), do: :ok

  def clear, do: :ok

  def get_and_update(_key, update_fun) do
    {current, updated} = update_fun.(nil)
    {:ok, {current, updated}}
  end

  def get_recent_kills, do: []

  def mget(_keys), do: {:error, :not_implemented}

  def get_kill(_kill_id), do: {:ok, %{}}
end
