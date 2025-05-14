defmodule WandererNotifier.Notifications.Helpers.Deduplication do
  @moduledoc """
  Unified deduplication helper for notifications, using Cachex for storage.
  Prevents duplicate notifications for systems, characters, and kills.
  """

  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  @behaviour WandererNotifier.Notifications.Helpers.DeduplicationBehaviour

  # Default TTL of 12 hours if not configured
  @default_ttl 12 * 60 * 60

  @type dedup_type :: :system | :character | :kill
  @spec check(type :: dedup_type, id :: String.t() | integer()) ::
          {:ok, :new | :duplicate} | {:error, term()}

  @doc """
  Checks if a notification for the given type and id is a duplicate.
  If not, marks it as seen for the deduplication TTL.

  Returns:
    - {:ok, :new} if this is a new notification (not a duplicate)
    - {:ok, :duplicate} if this is a duplicate notification
    - {:error, reason} on error
  """
  @impl true
  def check(type, id)
      when type in [:system, :character, :kill] and (is_binary(id) or is_integer(id)) do
    cache_key = dedup_key(type, id)

    try do
      case CacheRepo.get(cache_key) do
        {:ok, _} ->
          {:ok, :duplicate}

        _ ->
          # Get TTL duration from config or use default
          ttl = WandererNotifier.Config.notification_dedup_ttl() || @default_ttl
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

  defp dedup_key(:system, id), do: "system:#{id}"
  defp dedup_key(:character, id), do: "character:#{id}"
  defp dedup_key(:kill, id), do: "kill:#{id}"
end
