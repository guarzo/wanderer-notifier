defmodule WandererNotifier.MockCache do
  @moduledoc """
  Mock implementation of cache for testing
  """
  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  @impl true
  def get(_key), do: nil

  @impl true
  def set(_key, value, _ttl), do: {:ok, value}

  @impl true
  def put(_key, value), do: {:ok, value}

  @impl true
  def delete(_key), do: {:ok, true}

  @impl true
  def clear, do: {:ok, true}

  @impl true
  def get_and_update(key, fun) do
    {old_value, new_value} = fun.(nil)
    {:ok, _} = put(key, new_value)
    {old_value, new_value}
  end
end
