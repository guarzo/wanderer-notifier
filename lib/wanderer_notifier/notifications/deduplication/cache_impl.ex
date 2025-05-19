defmodule WandererNotifier.Notifications.Deduplication.CacheImpl do
  @moduledoc """
  Default implementation of the Deduplication behaviour using Cachex for storage.
  """

  @behaviour WandererNotifier.Notifications.Deduplication.Behaviour

  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Config

  @impl true
  def check(type, id)
      when type in [:system, :character, :kill] and (is_binary(id) or is_integer(id)) do
    cache_key = dedup_key(type, id)

    try do
      case CacheRepo.get(cache_key) do
        {:ok, _} ->
          {:ok, :duplicate}

        _ ->
          # Use centralized config for TTL
          ttl = Config.notification_dedup_ttl()
          # Mark as seen in the cache with appropriate TTL
          CacheRepo.set(cache_key, true, ttl)
          {:ok, :new}
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Clears a deduplication key from the cache (for testing or manual reset).
  """
  @impl true
  def clear_key(type, id)
      when type in [:system, :character, :kill] and (is_binary(id) or is_integer(id)) do
    cache_key = dedup_key(type, id)
    CacheRepo.delete(cache_key)
  end

  defp dedup_key(:system, id), do: CacheKeys.dedup_system(id)
  defp dedup_key(:character, id), do: CacheKeys.dedup_character(id)
  defp dedup_key(:kill, id), do: CacheKeys.dedup_kill(id)
end
