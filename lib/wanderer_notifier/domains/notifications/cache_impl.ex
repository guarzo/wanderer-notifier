defmodule WandererNotifier.Domains.Notifications.CacheImpl do
  @moduledoc """
  Cache-based implementation of notification deduplication.

  Uses the application cache to track recently processed notifications
  and prevent duplicate notifications within a configurable TTL window.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Cache

  @type notification_type :: :kill | :system | :character | :rally_point
  @type notification_id :: String.t() | integer()
  @type result :: {:ok, :new} | {:ok, :duplicate} | {:error, term()}

  # Default TTL for deduplication (30 minutes)
  @default_ttl :timer.minutes(30)

  # TTL per notification type
  @type_ttls %{
    kill: :timer.minutes(30),
    system: :timer.minutes(15),
    character: :timer.minutes(15),
    rally_point: :timer.minutes(5)
  }

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
    cache_key = build_cache_key(type, id)
    ttl = get_ttl(type)

    with result <- Cache.get(cache_key) do
      handle_cache_result(result, type, id, cache_key, ttl)
    end
  end

  def check(type, _id) do
    {:error, {:invalid_notification_type, type}}
  end

  defp handle_cache_result({:ok, _}, type, id, cache_key, _ttl) do
    # Key exists, this is a duplicate
    Logger.debug("Duplicate notification detected",
      type: type,
      id: id,
      cache_key: cache_key
    )

    {:ok, :duplicate}
  end

  defp handle_cache_result({:error, :not_found}, type, id, cache_key, ttl) do
    # Key doesn't exist, mark as seen and return new
    mark_notification_as_seen(type, id, cache_key, ttl)
  end

  defp mark_notification_as_seen(type, id, cache_key, ttl) do
    case Cache.put(cache_key, true, ttl) do
      :ok ->
        Logger.debug("New notification marked",
          type: type,
          id: id,
          cache_key: cache_key,
          ttl_ms: ttl
        )

        {:ok, :new}

      {:error, reason} ->
        Logger.error("Failed to mark notification as seen",
          type: type,
          id: id,
          cache_key: cache_key,
          error: reason
        )

        {:error, reason}
    end
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
    cache_key = build_cache_key(type, id)

    # Cache.delete always returns :ok
    Cache.delete(cache_key)

    Logger.debug("Deduplication key cleared",
      type: type,
      id: id,
      cache_key: cache_key
    )

    {:ok, :cleared}
  end

  def clear_key(type, _id) do
    {:error, {:invalid_notification_type, type}}
  end

  # Private functions

  @spec build_cache_key(notification_type(), notification_id()) :: String.t()
  defp build_cache_key(type, id) do
    "notification:dedup:#{type}:#{id}"
  end

  @spec get_ttl(notification_type()) :: pos_integer()
  defp get_ttl(type) do
    Map.get(@type_ttls, type, @default_ttl)
  end
end
