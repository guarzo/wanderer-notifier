defmodule WandererNotifier.Cache.HelpersBehaviour do
  @moduledoc """
  Behaviour for cache helpers.
  """

  @callback get(key :: String.t()) :: term() | nil
  @callback set(key :: String.t(), value :: term()) :: :ok | {:error, term()}
  @callback put(key :: String.t(), value :: term()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback clear() :: :ok | {:error, term()}
  @callback get_and_update(key :: String.t(), (term() -> {term(), term()})) ::
              {term(), term()} | {:error, term()}
  @callback get_tracked_systems() :: {:ok, list()} | {:error, term()}
end
