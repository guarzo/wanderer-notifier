defmodule WandererNotifier.Resources.KillmailPersistenceBehaviour do
  @moduledoc """
  Behaviour for killmail persistence.
  """

  @doc """
  Attempts to persist a killmail if it doesn't already exist.

  ## Parameters
    - killmail: The killmail data to persist

  ## Returns
    - {:ok, persisted_killmail} on success
    - {:error, reason} on failure
    - :ignored if the killmail already exists
  """
  @callback maybe_persist_killmail(killmail :: KillmailStruct.t() | map()) ::
              {:ok, map()} | {:error, term()} | :ignored

  @doc """
  Persists a killmail.

  ## Parameters
    - killmail: The killmail data to persist

  ## Returns
    - {:ok, persisted_killmail} on success
    - {:error, reason} on failure
    - :ignored if not relevant
  """
  @callback persist_killmail(killmail :: KillmailStruct.t()) ::
              {:ok, map()} | {:error, term()} | :ignored

  @doc """
  Persists a killmail with an explicitly provided character_id.

  ## Parameters
    - killmail: The killmail data to persist
    - character_id: The character ID to associate with this killmail, or nil to detect automatically

  ## Returns
    - {:ok, persisted_killmail} on success
    - {:error, reason} on failure
    - :ignored if not relevant
  """
  @callback persist_killmail(killmail :: KillmailStruct.t(), character_id :: integer() | nil) ::
              {:ok, map()} | {:error, term()} | :ignored
end
