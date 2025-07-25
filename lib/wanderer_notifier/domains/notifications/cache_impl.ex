defmodule WandererNotifier.Domains.Notifications.CacheImpl do
  @moduledoc """
  Cache implementation for notification deduplication.
  """

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Cache

  def check(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_key = cache_key(type, id)
    ttl = Config.deduplication_ttl()

    case Cache.get(cache_key) do
      {:ok, true} ->
        {:ok, :duplicate}

      {:error, :not_found} ->
        handle_cache_miss(cache_key, ttl)

      _ ->
        handle_cache_miss(cache_key, ttl)
    end
  end

  defp handle_cache_miss(cache_key, ttl) do
    Cache.put(cache_key, true, ttl)
    {:ok, :new}
  end

  def clear_key(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_key = cache_key(type, id)
    Cache.delete(cache_key)
    {:ok, :cleared}
  end

  # Private functions

  defp cache_key(type, id) do
    Cache.Keys.notification_dedup("#{type}:#{id}")
  end
end
