defmodule WandererNotifier.TestCacheStubs do
  @moduledoc """
  Stub implementation of the cache behavior for testing.
  """
  @behaviour WandererNotifier.Cache.CacheBehaviour

  @impl true
  def get(_key), do: nil

  @impl true
  def set(_key, _value, _ttl), do: :ok

  @impl true
  def put(_key, _value), do: :ok

  @impl true
  def delete(_key), do: :ok

  @impl true
  def clear, do: :ok

  @impl true
  def get_and_update(_key, fun) do
    {old, new} = fun.(nil)
    {old, new}
  end
end
