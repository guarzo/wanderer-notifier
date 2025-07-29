defmodule WandererNotifier.Domains.Notifications.Deduplication do
  @moduledoc """
  Behaviour for deduplication services.
  """

  @type notification_type :: :kill | :system | :character | :rally_point
  @type notification_id :: String.t() | integer()
  @type result :: {:ok, :new} | {:ok, :duplicate} | {:error, term()}

  @doc """
  Checks if a notification for the given type and id is a duplicate.
  If not, marks it as seen for the deduplication TTL.

  This function delegates to the configured implementation module.

  ## Parameters
    - type: The type of notification (:system, :character, :kill, or :rally_point)
    - id: The ID of the notification to check

  ## Returns
    - {:ok, :new} if this is a new notification (not a duplicate)
    - {:ok, :duplicate} if this is a duplicate notification
    - {:error, reason} on error
  """
  @spec check(notification_type(), notification_id()) :: result()
  def check(type, id) do
    deduplication_impl().check(type, id)
  end

  @doc """
  Clears a deduplication key from the cache (for testing or manual reset).

  This function delegates to the configured implementation module.

  ## Parameters
    - type: The type of notification (:system, :character, :kill, or :rally_point)
    - id: The ID of the notification to clear

  ## Returns
    - {:ok, :cleared} on success
    - {:error, reason} on failure
  """
  @spec clear_key(notification_type(), notification_id()) :: {:ok, :cleared} | {:error, term()}
  def clear_key(type, id) do
    if function_exported?(deduplication_impl(), :clear_key, 2) do
      deduplication_impl().clear_key(type, id)
    else
      {:error, :not_implemented}
    end
  end

  defp deduplication_impl do
    Application.get_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Domains.Notifications.CacheImpl
    )
  end
end
