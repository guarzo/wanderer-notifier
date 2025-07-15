defmodule WandererNotifier.Notifications.Deduplication.CacheImpl do
  @moduledoc """
  Cache implementation for notification deduplication.
  """

  @behaviour WandererNotifier.Notifications.Deduplication.DeduplicationBehaviour

  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Facade

  @impl true
  def check(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_key = cache_key(type, id)
    ttl = Config.deduplication_ttl()

    case Facade.get_custom(cache_key) do
      {:ok, true} ->
        {:ok, :duplicate}

      {:error, :not_found} ->
        handle_cache_miss(cache_key, ttl)

      _ ->
        handle_cache_miss(cache_key, ttl)
    end
  end

  defp handle_cache_miss(cache_key, ttl) do
    case Facade.put_custom(cache_key, true, ttl: ttl) do
      :ok -> {:ok, :new}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def clear_key(type, id) when is_atom(type) and (is_integer(id) or is_binary(id)) do
    cache_key = cache_key(type, id)
    Facade.delete_custom(cache_key)
  end

  # Private functions

  defp cache_key(type, id) do
    "deduplication:#{type}:#{id}"
  end
end
