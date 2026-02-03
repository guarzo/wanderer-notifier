defmodule WandererNotifier.Domains.Notifications.Deduplication do
  @moduledoc """
  Notification deduplication using the infrastructure cache.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Cache.Deduplication, as: CacheDedup

  @type notification_type :: :kill | :system | :character | :rally_point
  @type notification_id :: String.t() | integer()
  @type result :: {:ok, :new} | {:ok, :duplicate} | {:error, term()}

  @doc """
  Checks if a notification is a duplicate. If not, marks it as seen.
  """
  @spec check(notification_type(), notification_id()) :: result()
  def check(type, id) when type in [:kill, :system, :character, :rally_point] do
    dedup_type = map_to_dedup_type(type)
    identifier = to_string(id)

    case CacheDedup.check_and_mark(dedup_type, identifier) do
      {:ok, :new} ->
        Logger.debug("New notification marked", type: type, id: id)
        {:ok, :new}

      {:ok, :duplicate} ->
        Logger.debug("Duplicate notification detected", type: type, id: id)
        {:ok, :duplicate}

      {:error, reason} ->
        Logger.error("Deduplication check failed",
          type: type,
          id: id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  def check(type, _id), do: {:error, {:invalid_notification_type, type}}

  @doc """
  Clears a specific deduplication key from the cache.

  Use this to remove a previously marked notification from the deduplication cache,
  allowing it to be sent again if it reappears.
  """
  @spec clear_key(notification_type(), notification_id()) :: {:ok, :cleared} | {:error, term()}
  def clear_key(type, id) when type in [:kill, :system, :character, :rally_point] do
    dedup_type = map_to_dedup_type(type)
    identifier = to_string(id)
    key = build_dedup_key(dedup_type, identifier)

    case WandererNotifier.Infrastructure.Cache.delete(key) do
      {:ok, :deleted} ->
        Logger.debug("Cleared deduplication key", type: type, id: id)
        {:ok, :cleared}

      {:error, reason} ->
        Logger.error("Failed to clear deduplication key",
          type: type,
          id: id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  def clear_key(type, _id), do: {:error, {:invalid_notification_type, type}}

  defp build_dedup_key(:notification_kill, identifier),
    do: "notification:dedup:kill:#{identifier}"

  defp build_dedup_key(:notification_system, identifier),
    do: "notification:dedup:system:#{identifier}"

  defp build_dedup_key(:notification_character, identifier),
    do: "notification:dedup:character:#{identifier}"

  defp build_dedup_key(:notification_rally, identifier),
    do: "notification:dedup:rally:#{identifier}"

  # Private

  defp map_to_dedup_type(:kill), do: :notification_kill
  defp map_to_dedup_type(:system), do: :notification_system
  defp map_to_dedup_type(:character), do: :notification_character
  defp map_to_dedup_type(:rally_point), do: :notification_rally
end
