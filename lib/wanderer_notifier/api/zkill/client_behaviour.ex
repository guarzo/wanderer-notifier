defmodule WandererNotifier.Api.ZKill.ClientBehaviour do
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
  Gets kills for a specific character with optional limit and page.
  """
  @callback get_character_kills(character_id :: integer(), limit :: integer(), page :: integer()) ::
              {:ok, list(map())} | {:error, term()}
end
