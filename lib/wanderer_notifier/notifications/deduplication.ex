defmodule WandererNotifier.Notifications.Helpers.Deduplication do
  @moduledoc """
  Unified deduplication helper for notifications, using Cachex for storage.
  Prevents duplicate notifications for systems, characters, and kills.
  """

  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo

  @default_ttl 12 * 60 * 60 # 12 hours in seconds

  @type dedup_type :: :system | :character | :kill
  @spec check(type :: dedup_type, id :: String.t() | integer()) :: {:ok, :new | :duplicate} | {:error, term()}
  @doc """
  Checks if a notification for the given type and id is a duplicate.
  If not, marks it as seen for the deduplication TTL.

  Returns:
    - {:ok, :new} if this is a new notification (not a duplicate)
    - {:ok, :duplicate} if this is a duplicate notification
    - {:error, reason} on error
  """
  def check(type, id) when type in [:system, :character, :kill] and (is_binary(id) or is_integer(id)) do
    cache_key = dedup_key(type, id)
    ttl = dedup_ttl(type)

    try do
      case CacheRepo.get(cache_key) do
        {:ok, _} ->
          {:ok, :duplicate}
        _ ->
          CacheRepo.set(cache_key, true, ttl)
          {:ok, :new}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Clears a deduplication key from the cache (for testing or manual reset).
  """
  def clear_key(type, id) when type in [:system, :character, :kill] and (is_binary(id) or is_integer(id)) do
    cache_key = dedup_key(type, id)
    CacheRepo.delete(cache_key)
  end

  defp dedup_key(:system, id), do: "system:#{id}"
  defp dedup_key(:character, id), do: "character:#{id}"
  defp dedup_key(:kill, id), do: "kill:#{id}"

  defp dedup_ttl(_type), do: @default_ttl
end
