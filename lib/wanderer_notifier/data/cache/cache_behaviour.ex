defmodule WandererNotifier.Data.Cache.CacheBehaviour do
  @moduledoc """
  Defines the contract for cache implementations.
  """

  @callback get(key :: String.t()) :: term() | nil
  @callback set(key :: String.t(), value :: term(), ttl :: non_neg_integer()) ::
              :ok | {:error, term()}
  @callback put(key :: String.t(), value :: term()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback clear() :: :ok | {:error, term()}
  @callback get_and_update(key :: String.t(), (term() -> {term(), term()})) ::
              {term(), term()} | {:error, term()}
end
