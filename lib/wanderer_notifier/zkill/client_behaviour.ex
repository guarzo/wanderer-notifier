defmodule WandererNotifier.ZKill.ClientBehaviour do
  @moduledoc """
  Behaviour specification for the ZKillboard API client.
  """

  @doc """
  Gets a single killmail by its ID.
  """
  @callback get_single_killmail(kill_id :: integer()) :: {:ok, map()} | {:error, term()}

  @doc """
  Gets recent kills with an optional limit.
  """
  @callback get_recent_kills(limit :: integer()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Gets kills for a specific system with an optional limit.
  """
  @callback get_system_kills(system_id :: integer(), limit :: integer()) ::
              {:ok, list(map())} | {:error, term()}

  @doc """
  Gets kills for a specific character.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - date_range: Map with :start and :end DateTime (optional)
    - limit: Maximum number of kills to fetch (default: 100)
  """
  @callback get_character_kills(
              character_id :: integer(),
              date_range :: map() | nil,
              limit :: integer()
            ) :: {:ok, list(map())} | {:error, term()}
end
