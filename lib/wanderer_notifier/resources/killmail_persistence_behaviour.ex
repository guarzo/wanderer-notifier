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
  @callback maybe_persist_killmail(killmail :: map()) ::
              {:ok, map()} | {:error, term()} | :ignored

  @callback persist_killmail(killmail :: map()) :: :ok | {:error, term()}
end
