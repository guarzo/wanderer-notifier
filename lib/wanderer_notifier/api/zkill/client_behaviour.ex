defmodule WandererNotifier.Api.ZKill.ClientBehaviour do
  @moduledoc """
  Behaviour definition for the ZKill API client.
  Defines the contract that any implementation must fulfill.
  """

  @doc """
  Retrieves a single killmail from zKillboard by ID.

  ## Parameters
  - `kill_id`: The ID of the killmail to retrieve

  ## Returns
  - `{:ok, killmail}`: The killmail data
  - `{:error, reason}`: If an error occurred
  """
  @callback get_single_killmail(kill_id :: integer()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Retrieves recent kills from zKillboard.

  ## Parameters
  - `limit`: The maximum number of kills to retrieve (default: 10)

  ## Returns
  - `{:ok, kills}`: A list of recent kills
  - `{:error, reason}`: If an error occurred
  """
  @callback get_recent_kills(limit :: integer()) ::
              {:ok, list(map())} | {:error, term()}

  @doc """
  Retrieves kills for a specific system from zKillboard.

  ## Parameters
  - `system_id`: The ID of the system to get kills for
  - `limit`: The maximum number of kills to retrieve (default: 5)

  ## Returns
  - `{:ok, kills}`: A list of kills for the system
  - `{:error, reason}`: If an error occurred
  """
  @callback get_system_kills(system_id :: integer(), limit :: integer()) ::
              {:ok, list(map())} | {:error, term()}

  @doc """
  Gets recent kill information for a specific character from zKillboard.

  ## Parameters
  - `character_id`: The character ID to find kills for
  - `limit`: Maximum number of kills to retrieve (defaults to 25)
  - `page`: Page number for pagination (defaults to 1)

  ## Returns
  - `{:ok, kills}`: List of kills for the character
  - `{:error, reason}`: If an error occurred
  """
  @callback get_character_kills(character_id :: integer(), limit :: integer(), page :: integer()) ::
              {:ok, list(map())} | {:error, term()}
end
