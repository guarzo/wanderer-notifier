defmodule WandererNotifier.Notifications.Deduplication.Behaviour do
  @moduledoc """
  Behaviour for deduplication functionality.
  Defines the contract for modules that handle notification deduplication.
  """

  @doc """
  Checks if a notification for the given type and id is a duplicate.
  If not, marks it as seen for the deduplication TTL.

  ## Parameters
    - type: The type of notification (:system, :character, or :kill)
    - id: The ID of the notification to check

  ## Returns
    - {:ok, :new} if this is a new notification (not a duplicate)
    - {:ok, :duplicate} if this is a duplicate notification
    - {:error, reason} on error
  """
  @callback check(type :: :system | :character | :kill, id :: String.t() | integer()) ::
              {:ok, :new | :duplicate} | {:error, term()}

  @doc """
  Clears a deduplication key from the cache (for testing or manual reset).

  ## Parameters
    - type: The type of notification (:system, :character, or :kill)
    - id: The ID of the notification to clear

  ## Returns
    - {:ok, :cleared} on success
    - {:error, reason} on failure
  """
  @callback clear_key(type :: :system | :character | :kill, id :: String.t() | integer()) ::
              {:ok, :cleared} | {:error, term()}
end
