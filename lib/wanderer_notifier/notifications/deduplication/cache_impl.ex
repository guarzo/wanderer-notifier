defmodule WandererNotifier.Notifications.Deduplication.CacheImpl do
  @moduledoc """
  Cache implementation for notification deduplication.
  """

  @behaviour WandererNotifier.Notifications.Deduplication.Behaviour

  @impl true
  def check(key, ttl) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = cache_key(key)

    case Cachex.get(cache_name, cache_key) do
      {:ok, true} ->
        {:ok, :duplicate}

      _ ->
        Cachex.put(cache_name, cache_key, true, ttl: ttl)
        {:ok, :new}
    end
  end

  @impl true
  def clear_key(key, _ttl) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = cache_key(key)
    Cachex.del(cache_name, cache_key)
  end

  # Private functions

  defp cache_key(key) do
    "deduplication:#{key}"
  end
end
