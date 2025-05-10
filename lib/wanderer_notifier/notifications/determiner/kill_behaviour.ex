defmodule WandererNotifier.Notifications.Determiner.KillBehaviour do
  @moduledoc """
  Behaviour for killmail notification determination.
  Defines the contract for modules that determine if a kill should trigger a notification.
  """

  @doc """
  Determines if a kill notification should be sent.

  ## Parameters
  - kill_data: The killmail data to evaluate

  ## Returns
  - {:ok, %{should_notify: boolean, reason: String.t() | nil}} indicating if notification should be sent
  - {:error, reason} on error
  """
  @callback should_notify?(kill_data :: map()) ::
              {:ok, %{should_notify: boolean(), reason: String.t() | nil}}
              | {:error, term()}

  @doc """
  Gets the system ID from a kill.

  ## Parameters
    - kill: The kill data to check

  ## Returns
    - The system ID as a string
  """
  @callback get_kill_system_id(kill :: struct() | map()) :: String.t()

  @doc """
  Checks if a system is being tracked.

  ## Parameters
    - system_id: The ID of the system to check

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  @callback tracked_system?(system_id :: String.t() | integer()) :: boolean()

  @doc """
  Checks if a killmail involves a tracked character.

  ## Parameters
    - killmail: The killmail data to check

  ## Returns
    - true if the killmail involves a tracked character
    - false otherwise
  """
  @callback has_tracked_character?(killmail :: struct() | map()) :: boolean()

  @doc """
  Gets the list of tracked characters involved in a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - List of tracked character IDs involved in the kill
  """
  @callback get_tracked_characters(killmail :: struct() | map()) :: list(String.t())

  @doc """
  Determines if tracked characters are victims in a kill.

  ## Parameters
    - killmail: The killmail to check
    - tracked_characters: List of tracked character IDs

  ## Returns
    - true if any tracked character is a victim
    - false if all tracked characters are attackers
  """
  @callback are_tracked_characters_victims?(
              killmail :: struct() | map(),
              tracked_characters :: list(String.t())
            ) ::
              boolean()

  @doc """
  Checks if a character is being tracked.

  ## Parameters
    - character_id: The ID of the character to check

  ## Returns
    - true if the character is tracked
    - false otherwise
  """
  @callback tracked_character?(character_id :: String.t() | integer()) :: boolean()
end
