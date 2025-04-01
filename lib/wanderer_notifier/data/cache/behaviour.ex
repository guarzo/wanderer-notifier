defmodule WandererNotifier.Data.Cache.Behaviour do
  @moduledoc """
  Behaviour definition for cache implementations.
  Defines the contract that any cache implementation must fulfill.
  """

  @callback get(key :: term()) :: {:ok, term() | nil} | {:error, term()}
  @callback put(key :: term(), value :: term(), opts :: Keyword.t()) ::
              {:ok, boolean()} | {:error, term()}
  @callback delete(key :: term()) :: {:ok, boolean()} | {:error, term()}
  @callback exists?(key :: term()) :: {:ok, boolean()} | {:error, term()}
  @callback update(key :: term(), update_fn :: function(), default :: term()) ::
              {:ok, term()} | {:error, term()}
end
