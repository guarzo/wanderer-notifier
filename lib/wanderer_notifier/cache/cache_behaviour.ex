defmodule WandererNotifier.Cache.CacheBehaviour do
  @moduledoc """
  Defines the behavior for cache implementations
  """

  @callback get(key :: any()) :: {:ok, any()} | {:error, any()}
  @callback set(key :: any(), value :: any(), ttl :: integer() | nil) :: :ok | {:error, any()}
  @callback put(key :: any(), value :: any()) :: :ok | {:error, any()}
  @callback delete(key :: any()) :: :ok | {:error, any()}
  @callback clear() :: :ok | {:error, any()}
  @callback get_and_update(key :: any(), update_fun :: (any() -> {any(), any()})) ::
              {:ok, any()} | {:error, any()}
end
