defmodule WandererNotifier.Api.ZKill.ClientBehaviour do
  @moduledoc """
  Behaviour module defining the contract for ZKillboard API clients.
  This ensures consistent interfaces for all implementations.
  """

  @doc """
  Gets a single killmail by its ID.

  ## Parameters
    - `kill_id` - The killmail ID to fetch

  ## Returns
    - `{:ok, data}` where data is a map or list containing the killmail data
    - `{:error, reason}` on failure
  """
  @callback get_single_killmail(kill_id :: integer() | binary()) ::
              {:ok, map() | list(map())} | {:error, any()}

  @doc """
  Gets recent kills.

  ## Parameters
    - `limit` - Maximum number of kills to return

  ## Returns
    - `{:ok, kills}` where kills is a list of killmail data
    - `{:error, reason}` on failure
  """
  @callback get_recent_kills(limit :: integer()) :: {:ok, list(map())} | {:error, any()}

  @doc """
  Gets kills for a specific system.

  ## Parameters
    - `system_id` - The system ID to fetch kills for
    - `limit` - Maximum number of kills to return

  ## Returns
    - `{:ok, kills}` where kills is a list of killmail data
    - `{:error, reason}` on failure
  """
  @callback get_system_kills(system_id :: integer() | binary(), limit :: integer()) ::
              {:ok, list(map())} | {:error, any()}

  @doc """
  Gets kills for a specific character.

  ## Parameters
    - `character_id` - The character ID to fetch kills for
    - `date_range` - Optional date range to filter kills
    - `limit` - Maximum number of kills to return

  ## Returns
    - `{:ok, kills}` where kills is a list of killmail data
    - `{:error, reason}` on failure
  """
  @callback get_character_kills(
              character_id :: integer() | binary(),
              date_range :: map() | nil,
              limit :: integer()
            ) :: {:ok, list(map())} | {:error, any()}
end
