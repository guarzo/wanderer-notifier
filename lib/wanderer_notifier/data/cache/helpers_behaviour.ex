defmodule WandererNotifier.Data.Cache.HelpersBehaviour do
  @moduledoc """
  Behaviour specification for cache helper functions.
  """

  @doc """
  Gets cached kills for a given ID.
  """
  @callback get_cached_kills(integer() | String.t()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Gets tracked systems from cache.
  """
  @callback get_tracked_systems() :: list(map())

  @doc """
  Gets tracked characters from cache.
  """
  @callback get_tracked_characters() :: list(map())

  @doc """
  Gets cached ship name.
  """
  @callback get_ship_name(integer()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Gets cached character name.
  """
  @callback get_character_name(integer()) :: {:ok, String.t()} | {:error, term()}
end
