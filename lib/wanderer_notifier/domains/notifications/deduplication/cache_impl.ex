defmodule WandererNotifier.Domains.Notifications.Deduplication.CacheImpl do
  @moduledoc """
  Cache implementation for notification deduplication.
  """

  @behaviour WandererNotifier.Domains.Notifications.Deduplication.DeduplicationBehaviour

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Infrastructure.Cache.KeysSimple, as: Keys

  @impl true
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
    case Cache.put(cache_key, true, ttl) do
      :ok -> {:ok, :new}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def clear_key(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_key = cache_key(type, id)
    Cache.delete(cache_key)
  end

  # Private functions

  defp cache_key(type, id) do
    Keys.notification_dedup("#{type}:#{id}")
  end
end
