defmodule WandererNotifier.Test.Support.TestCacheStubs do
  @moduledoc """
  Test stubs for cache behaviour.
  """

  @behaviour WandererNotifier.Infrastructure.Cache.CacheBehaviour

  @impl true
  def get(_key, _opts \\ []), do: {:ok, nil}

  @impl true
  def set(_key, value, _ttl), do: {:ok, value}

  @impl true
  def put(_key, value), do: {:ok, value}

  @impl true
  def delete(_key), do: :ok

  @impl true
  def clear, do: :ok

  @impl true
  def get_and_update(_key, update_fun) do
    {current, updated} = update_fun.(nil)
    {:ok, {current, updated}}
  end

  @impl true
  def get_recent_kills, do: []

  @impl true
  def mget(_keys), do: {:error, :not_implemented}

  @impl true
  def get_kill(_kill_id), do: {:ok, %{}}
end
