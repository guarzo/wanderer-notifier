defmodule WandererNotifier.Data.Cache.RepositoryBehaviour do
  @moduledoc """
  Behaviour for cache repository operations.
  """

  @callback get(key :: String.t()) :: any()
  @callback put(key :: String.t(), value :: any()) :: :ok
  @callback delete(key :: String.t()) :: :ok
  @callback get_and_update(key :: String.t(), (any() -> {any(), any()})) :: any()
  @callback exists?(key :: String.t()) :: boolean()
  @callback set(key :: String.t(), value :: any(), ttl :: non_neg_integer() | nil) :: :ok
  @callback get_tracked_characters() :: list(map())
  @callback clear() :: :ok
end
