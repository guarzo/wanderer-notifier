defmodule WandererNotifier.Data.Cache.CacheTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "mocks Cache operations successfully" do
    # Set up mock expectations
    WandererNotifier.MockCache
    |> expect(:get, fn key ->
      assert key == "test_key"
      {:ok, "test_value"}
    end)
    |> expect(:put, fn key, value, _opts ->
      assert key == "new_key"
      assert value == "new_value"
      {:ok, true}
    end)

    # Test the get operation
    result = WandererNotifier.MockCache.get("test_key")
    assert result == {:ok, "test_value"}

    # Test the put operation
    put_result = WandererNotifier.MockCache.put("new_key", "new_value", [])
    assert put_result == {:ok, true}
  end
end
