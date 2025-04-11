defmodule WandererNotifier.Processing.Killmail.PersistenceBehaviour do
  @moduledoc """
  Behavior module for Killmail Persistence operations.

  This defines the contract that any killmail persistence implementation must follow.
  """

  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  @doc """
  Persists a killmail to the database.

  ## Parameters
    - killmail: The KillmailData struct to persist
    - character_id: Optional character ID that initiated the processing

  ## Returns
    - {:ok, persisted_killmail, created} if successful
    - {:error, reason} if there was an error
  """
  @callback persist_killmail(KillmailData.t(), integer() | nil) ::
              {:ok, KillmailData.t(), boolean()} | {:error, any()}

  @doc """
  Gets all killmails for a specific character.

  ## Parameters
    - character_id: The character ID to look for

  ## Returns
    - {:ok, killmails} with a list of killmails involving the character
    - {:error, reason} if there's an error
  """
  @callback get_killmails_for_character(integer() | String.t()) ::
              {:ok, list(KillmailResource.t())} | {:error, any()}

  @doc """
  Gets all killmails for a specific solar system.

  ## Parameters
    - system_id: The solar system ID to look for

  ## Returns
    - {:ok, killmails} with a list of killmails in the system
    - {:error, reason} if there's an error
  """
  @callback get_killmails_for_system(integer() | String.t()) ::
              {:ok, list(KillmailResource.t())} | {:error, any()}

  @doc """
  Gets killmails for a specific character within a date range.

  ## Parameters
    - character_id: The character ID to look for
    - from_date: The start date (inclusive)
    - to_date: The end date (inclusive)
    - limit: Maximum number of killmails to return (default: 100)

  ## Returns
    - {:ok, killmails} with a list of killmails involving the character in the date range
    - {:error, reason} if there's an error
  """
  @callback get_character_killmails(
              integer() | String.t(),
              DateTime.t(),
              DateTime.t(),
              integer()
            ) :: {:ok, list(KillmailResource.t())} | {:error, any()}

  @doc """
  Checks if a killmail exists for a character with a specific role.

  ## Parameters
    - killmail_id: The killmail ID
    - character_id: The character ID
    - role: The role (:victim or :attacker)

  ## Returns
    - {:ok, true} if the killmail exists with the character in the specified role
    - {:ok, false} if not found
    - {:error, reason} if there's an error
  """
  @callback exists?(integer() | String.t(), integer() | String.t(), atom()) ::
              {:ok, boolean()} | {:error, any()}

  @doc """
  Gets the total number of killmails in the database.

  ## Returns
    - The count of killmails
  """
  @callback count_total_killmails() :: integer()
end
