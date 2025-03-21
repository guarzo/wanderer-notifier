defmodule WandererNotifier.Cache.Behaviour do
  @moduledoc """
  Defines the behaviour for cache operations to enable mocking in tests.
  """

  @callback get(key :: term()) :: {:ok, term() | nil} | {:error, term()}
  @callback put(key :: term(), value :: term(), opts :: Keyword.t()) ::
              {:ok, boolean()} | {:error, term()}
  @callback delete(key :: term()) :: {:ok, boolean()} | {:error, term()}
  @callback exists?(key :: term()) :: {:ok, boolean()} | {:error, term()}
  @callback update(key :: term(), update_fn :: function(), default :: term()) ::
              {:ok, term()} | {:error, term()}
end
