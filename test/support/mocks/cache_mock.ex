defmodule WandererNotifier.Test.Support.Mocks.CacheMock do
  @moduledoc """
  Mock implementation of the cache behavior for testing.
  """

  @behaviour WandererNotifier.Cache.Behaviour

  @impl true
  def get(key), do: {:ok, Process.get({:cache, key})}

  @impl true
  def set(key, value, _ttl) do
    Process.put({:cache, key}, value)
    {:ok, value}
  end

  @impl true
  def put(key, value) do
    Process.put({:cache, key}, value)
    {:ok, value}
  end

  @impl true
  def delete(key) do
    Process.delete({:cache, key})
    :ok
  end

  @impl true
  def clear do
    # This is a simplified clear that only clears cache-related process dictionary entries
    Process.get_keys()
    |> Enum.filter(fn
      {:cache, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)

    :ok
  end

  @impl true
  def get_and_update(key, update_fun) do
    current = Process.get({:cache, key})
    {current_value, new_value} = update_fun.(current)
    Process.put({:cache, key}, new_value)
    {:ok, {current_value, new_value}}
  end

  @impl true
  def get_recent_kills do
    case get(WandererNotifier.Cache.Keys.zkill_recent_kills()) do
      {:ok, kills} when is_list(kills) -> kills
      _ -> []
    end
  end
end
