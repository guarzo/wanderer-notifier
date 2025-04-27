defmodule WandererNotifier.Cache.RepositoryBehaviour do
  @moduledoc """
  Behaviour for cache repository implementations.
  """

  @callback get(key :: String.t()) :: term() | nil
  @callback set(key :: String.t(), value :: term(), ttl :: non_neg_integer()) ::
              :ok | {:error, term()}
  @callback put(key :: String.t(), value :: term()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback clear() :: :ok | {:error, term()}
  @callback get_and_update(
              key :: String.t(),
              update_fun :: (term() -> {term(), term()}),
              ttl :: non_neg_integer() | nil
            ) ::
              {term(), term()} | {:error, term()}
  @callback get_recent_kills() :: list()
end
