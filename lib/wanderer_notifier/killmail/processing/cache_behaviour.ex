defmodule WandererNotifier.Killmail.Processing.CacheBehaviour do
  @moduledoc """
  Behaviour definition for killmail caching implementations.
  """

  alias WandererNotifier.Killmail.Core.Data

  @doc """
  Checks if a killmail exists in the cache.
  """
  @callback in_cache?(integer()) :: boolean()

  @doc """
  Caches a killmail.
  """
  @callback cache(Data.t()) :: {:ok, Data.t()} | {:error, any()}
end
