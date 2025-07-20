defmodule WandererNotifier.Test.Support.CacheHelpers do
  @moduledoc """
  Helper functions for working with cache in tests.
  Provides utilities for both mock cache and ETS adapter usage.
  """

  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Infrastructure.Cache.KeysSimple, as: Keys

  @doc """
  Sets up a clean cache for testing.
  Can be used in ExUnit setup blocks.
  """
  def setup_cache(context \\ %{}) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)

    # Ensure the ETS table exists
    ensure_ets_table_exists(cache_name)

    # Clear any existing cache data
    clear_cache(cache_name)

    # Initialize with empty recent kills list
    Cache.put("zkill:recent_kills", [], :timer.hours(1))

    Map.put(context, :cache_name, cache_name)
  end

  defp ensure_ets_table_exists(cache_name) do
    # Check if the cache process is already running
    case Registry.lookup(WandererNotifier.Infrastructure.Cache.Registry, cache_name) do
      [] ->
        # Start the ETS cache if not already started
        {:ok, _} = WandererNotifier.Infrastructure.Cache.ETSCache.start_link(name: cache_name)

      _ ->
        :ok
    end
  end

  @doc """
  Clears all data from the cache.
  """
  def clear_cache(cache_name) do
    # For ETS adapter, we need to delete all keys
    # Since ETS doesn't have a built-in clear, we'll delete known patterns
    known_prefixes = ["map:", "esi:", "tracked:", "zkill:", "recent:", "dedup:", "config:"]

    for prefix <- known_prefixes do
      clear_by_prefix(cache_name, prefix)
    end

    :ok
  end

  @doc """
  Adds test data to the cache.
  """
  def seed_cache(_cache_name, data) do
    Enum.each(data, fn {key, value} ->
      Cache.put(key, value, :timer.hours(1))
    end)
  end

  @doc """
  Gets a value from the cache, returning nil if not found.
  """
  def get_cached(_cache_name, key) do
    case Cache.get(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  @doc """
  Helper to create cache expectations for Mox-based tests.
  """
  def expect_cache_get(mock_module, key, value) do
    Mox.expect(mock_module, :get, fn ^key, _opts -> {:ok, value} end)
  end

  @doc """
  Helper to stub cache operations for an entire test.
  """
  def stub_cache_operations(mock_module, stubs \\ %{}) do
    default_stubs = %{
      get: {:ok, nil},
      set: {:ok, true},
      delete: :ok,
      clear: :ok
    }

    stubs = Map.merge(default_stubs, stubs)

    Enum.each(stubs, fn {operation, return_value} ->
      Mox.stub(mock_module, operation, fn _args -> return_value end)
    end)
  end

  # Private helpers

  defp clear_by_prefix(cache_name, prefix) do
    # For ETS adapter, we would need to implement pattern matching
    # Since ETS tables are public, we can directly manipulate them
    case :ets.info(cache_name) do
      :undefined ->
        :ok

      _ ->
        # Match all keys starting with prefix
        match_spec = [{{:"$1", :_, :_}, [{:is_binary, :"$1"}], [:"$1"]}]
        keys = :ets.select(cache_name, match_spec)

        matching_keys = Enum.filter(keys, &String.starts_with?(&1, prefix))
        Enum.each(matching_keys, &:ets.delete(cache_name, &1))
        :ok
    end
  catch
    _, _ -> :ok
  end
end
