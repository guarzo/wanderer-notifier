defmodule WandererNotifier.Notifications.Deduplication.CacheImpl do
  @moduledoc """
  Cache implementation for notification deduplication.
  """

  @behaviour WandererNotifier.Notifications.Deduplication.DeduplicationBehaviour

  alias WandererNotifier.Config

  @impl true
  def check(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_name = Config.cache_name()
    cache_key = cache_key(type, id)
    ttl = Config.deduplication_ttl()

    case Cachex.get(cache_name, cache_key) do
      {:ok, true} ->
        {:ok, :duplicate}

      _ ->
        Cachex.put(cache_name, cache_key, true, ttl: ttl)
        {:ok, :new}
    end
  end

  @impl true
  def clear_key(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_name = Config.cache_name()
    cache_key = cache_key(type, id)
    Cachex.del(cache_name, cache_key)
  end

  # Private functions

  defp cache_key(type, id) do
    "deduplication:#{type}:#{id}"
  end
end
