defmodule ChainKills.Cache.Repository do
  @moduledoc """
  Cachex repository for ChainKills.
  """
  require Logger

  @cache_name :chainkills_cache

  def start_link(_args \\ []) do
    Cachex.start_link(@cache_name, [])
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  # Set with TTL
  def set(key, value, ttl) do
    Cachex.put(@cache_name, key, value, ttl: ttl)
  end

  # Simple put function without TTL, for storing kill IDs
  def put(key, value) do
    Cachex.put(@cache_name, key, value)
  end
end
