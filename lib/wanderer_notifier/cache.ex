defmodule WandererNotifier.Cache do
  @moduledoc """
  Main cache interface module that provides convenience functions for caching operations.
  This module delegates to the underlying cache adapter (Cachex or ETSCache).
  """

  alias WandererNotifier.Cache.Adapter
  alias WandererNotifier.Cache.Config

  # Re-export the Keys module for convenience
  defdelegate map_systems(), to: WandererNotifier.Cache.Keys, as: :map_systems
  defdelegate character_list(), to: WandererNotifier.Cache.Keys, as: :character_list

  @doc """
  Gets a value from the cache.

  ## Examples

      iex> WandererNotifier.Cache.get("map:system:30000142")
      {:ok, %{name: "Jita", security: 0.9}}
      
      iex> WandererNotifier.Cache.get("nonexistent")
      {:ok, nil}
  """
  @spec get(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get(key, opts \\ []) do
    cache_name = Config.cache_name(opts)
    Adapter.get(cache_name, key)
  end

  @doc """
  Sets a value in the cache without TTL.

  ## Examples

      iex> WandererNotifier.Cache.put("map:system:30000142", %{name: "Jita"})
      {:ok, true}
  """
  @spec put(String.t(), term(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def put(key, value, opts \\ []) do
    cache_name = Config.cache_name(opts)
    Adapter.put(cache_name, key, value)
  end

  @doc """
  Sets a value in the cache with a TTL.

  ## Examples

      iex> WandererNotifier.Cache.set("map:system:30000142", %{name: "Jita"}, :timer.hours(1))
      {:ok, true}
      
      iex> WandererNotifier.Cache.set("config:feature", true, :infinity)
      {:ok, true}
  """
  @spec set(String.t(), term(), :infinity | non_neg_integer(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def set(key, value, ttl, opts \\ []) do
    cache_name = Config.cache_name(opts)
    Adapter.set(cache_name, key, value, ttl)
  end

  @doc """
  Deletes a value from the cache.

  ## Examples

      iex> WandererNotifier.Cache.delete("map:system:30000142")
      {:ok, true}
  """
  @spec delete(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def delete(key, opts \\ []) do
    cache_name = Config.cache_name(opts)
    Adapter.del(cache_name, key)
  end

  @doc """
  Clears all values from the cache.

  ## Examples

      iex> WandererNotifier.Cache.clear()
      {:ok, true}
  """
  @spec clear(keyword()) :: {:ok, boolean()} | {:error, term()}
  def clear(opts \\ []) do
    cache_name = Config.cache_name(opts)
    Adapter.clear(cache_name)
  end
end
