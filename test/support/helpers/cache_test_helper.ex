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
  def assert_cache_put(key, value) do
    assert :ok = Cache.put(key, value)
    assert {:ok, ^value} = Cache.get(key)
  end

  @doc """
  Asserts that a Cache.put operation with TTL succeeds and the value is correctly stored.

  ## Examples

      assert_cache_put("test:key", "test_value", :timer.hours(1))
  """
  def assert_cache_put(key, value, ttl) do
    assert :ok = Cache.put(key, value, ttl)
    assert {:ok, ^value} = Cache.get(key)
  end
end
