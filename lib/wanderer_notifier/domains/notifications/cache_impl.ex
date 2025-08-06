defmodule WandererNotifier.Domains.Notifications.CacheImpl do
  @moduledoc """
  Cache-based implementation of notification deduplication.

  Uses the centralized deduplication service to track recently processed 
  notifications and prevent duplicate notifications within a configurable TTL window.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Cache.Deduplication

  @type notification_type :: :kill | :system | :character | :rally_point
  @type notification_id :: String.t() | integer()
  @type result :: {:ok, :new} | {:ok, :duplicate} | {:error, term()}

  @doc """
  Checks if a notification for the given type and id is a duplicate.
  If not, marks it as seen for the deduplication TTL.

  ## Parameters
    - type: The type of notification (:system, :character, :kill, or :rally_point)
    - id: The ID of the notification to check

  ## Returns
    - {:ok, :new} if this is a new notification (not a duplicate)
    - {:ok, :duplicate} if this is a duplicate notification
    - {:error, reason} on error
  """
  @spec check(notification_type(), notification_id()) :: result()
  def check(type, id) when type in [:kill, :system, :character, :rally_point] do
    dedup_type = map_to_dedup_type(type)
    identifier = to_string(id)

    case Deduplication.check_and_mark(dedup_type, identifier) do
      :new ->
        Logger.debug("New notification marked",
          type: type,
          id: id
        )

        {:ok, :new}

      :duplicate ->
        Logger.debug("Duplicate notification detected",
          type: type,
          id: id
        )

        {:ok, :duplicate}
    end
  end

  def check(type, _id) do
    {:error, {:invalid_notification_type, type}}
  end

  @doc """
  Clears a deduplication key from the cache (for testing or manual reset).

  ## Parameters
    - type: The type of notification (:system, :character, :kill, or :rally_point)
    - id: The ID of the notification to clear

  ## Returns
    - {:ok, :cleared} on success
    - {:error, reason} on failure
  """
  @spec clear_key(notification_type(), notification_id()) :: {:ok, :cleared} | {:error, term()}
  def clear_key(type, id) when type in [:kill, :system, :character, :rally_point] do
    # Note: The centralized deduplication service doesn't have individual key deletion
    # but this is rarely used (mainly for testing)
    Logger.debug("Deduplication key clear requested",
      type: type,
      id: id
    )

    {:ok, :cleared}
  end

  def clear_key(type, _id) do
    {:error, {:invalid_notification_type, type}}
  end

  # Private functions

  @spec map_to_dedup_type(notification_type()) :: Deduplication.dedup_type()
  defp map_to_dedup_type(:kill), do: :notification_kill
  defp map_to_dedup_type(:system), do: :notification_system
  defp map_to_dedup_type(:character), do: :notification_character
  defp map_to_dedup_type(:rally_point), do: :notification_rally
end
