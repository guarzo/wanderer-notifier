defmodule WandererNotifier.Helpers.CacheHelpersBehaviour do
  @moduledoc """
  Behaviour definition for cache helper functions.
  Defines the contract that any implementation must fulfill.
  """

  @doc """
  Retrieves the list of tracked characters from cache or database.

  ## Returns
  - `list(map())`: List of tracked character maps, each containing character information
  """
  @callback get_tracked_characters() :: list(map())

  @callback get_character_name(character_id :: integer()) ::
              {:ok, String.t()} | {:error, term()}

  @callback get_ship_name(ship_type_id :: integer()) ::
              {:ok, String.t()} | {:error, term()}

  @callback get_cached_kills(character_id :: integer()) :: {:ok, list(map())} | {:error, term()}
end
