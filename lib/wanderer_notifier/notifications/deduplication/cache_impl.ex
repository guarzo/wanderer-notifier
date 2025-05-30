defmodule WandererNotifier.Notifications.Deduplication.CacheImpl do
  @moduledoc """
  Cache implementation for notification deduplication.
  """

  @behaviour WandererNotifier.Notifications.Deduplication.Behaviour

  @impl true
  def check(type, id) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = cache_key(type, id)
    ttl = Application.get_env(:wanderer_notifier, :deduplication_ttl, 3600)

    case Cachex.get(cache_name, cache_key) do
      {:ok, true} ->
        {:ok, :duplicate}

      _ ->
        Cachex.put(cache_name, cache_key, true, ttl: ttl)
        {:ok, :new}
    end
  end

  @impl true
  def clear_key(type, id) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    cache_key = cache_key(type, id)
    Cachex.del(cache_name, cache_key)
  end

  # Private functions

  defp cache_key(type, id) do
    "deduplication:#{type}:#{id}"
  end
end
