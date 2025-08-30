defmodule WandererNotifier.Test.Helpers.CacheTestHelper do
  @moduledoc """
  Helper functions for cache assertions in tests.
  """

  alias WandererNotifier.Infrastructure.Cache

  import ExUnit.Assertions

  @doc """
  Asserts that a Cache.put operation succeeds and the value is correctly stored.

  This helper improves test determinism by verifying both the put operation
  and that the value can be retrieved.

  ## Examples

      assert_cache_put("test:key", "test_value")
      assert_cache_put(Cache.Keys.map_characters(), characters)
  """
  @spec assert_cache_put(term(), term()) :: :ok
  def assert_cache_put(key, value) do
    assert :ok = Cache.put(key, value)
    assert {:ok, ^value} = Cache.get(key)
    :ok
  end

  @doc """
  Asserts that a Cache.put operation with TTL succeeds and the value is correctly stored.

  ## Examples

      assert_cache_put("test:key", "test_value", :timer.hours(1))
  """
  @spec assert_cache_put(term(), term(), integer()) :: :ok
  def assert_cache_put(key, value, ttl) do
    assert :ok = Cache.put(key, value, ttl)
    assert {:ok, ^value} = Cache.get(key)
    :ok
  end
end
