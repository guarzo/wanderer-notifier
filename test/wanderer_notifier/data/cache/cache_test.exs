defmodule WandererNotifier.Data.CacheTest do
  # Disable async since we're using shared ETS tables
  use ExUnit.Case, async: false
  # Suppress log output during tests
  @moduletag :capture_log

  alias WandererNotifier.Data.Cache

  setup_all do
    # Ensure tables exist before any test
    table_opts = [
      :named_table,
      :public,
      :set,
      {:write_concurrency, false},
      {:read_concurrency, true}
    ]

    # Create tables if they don't exist
    if :ets.whereis(:cache_table) == :undefined do
      :ets.new(:cache_table, table_opts)
    end

    if :ets.whereis(:locks_table) == :undefined do
      :ets.new(:locks_table, table_opts)
    end

    on_exit(fn ->
      # Clean up tables after all tests
      :ets.delete_all_objects(:cache_table)
      :ets.delete_all_objects(:locks_table)
    end)

    :ok
  end

  setup do
    # Clean tables before each test
    :ets.delete_all_objects(:cache_table)
    :ets.delete_all_objects(:locks_table)
    :ok
  end

  describe "get/1" do
    test "returns value when key exists" do
      key = "test_key"
      value = "test_value"
      :ets.insert(:cache_table, {key, value})

      assert {:ok, ^value} = Cache.get(key)
    end

    test "returns error when key does not exist" do
      assert {:error, :not_found} = Cache.get("nonexistent_key")
    end
  end

  describe "set/3" do
    test "sets value successfully" do
      key = "test_key"
      value = "test_value"

      assert {:ok, ^value} = Cache.set(key, value)
      assert [{^key, ^value}] = :ets.lookup(:cache_table, key)
    end
  end

  describe "put/3" do
    test "puts value successfully" do
      key = "test_key"
      value = "test_value"

      assert {:ok, ^value} = Cache.put(key, value)
      assert [{^key, ^value}] = :ets.lookup(:cache_table, key)
    end
  end

  describe "delete/1" do
    test "deletes value successfully" do
      key = "test_key"
      value = "test_value"
      :ets.insert(:cache_table, {key, value})

      assert :ok = Cache.delete(key)
      assert [] = :ets.lookup(:cache_table, key)
    end
  end

  describe "clear/0" do
    test "clears all values" do
      :ets.insert(:cache_table, {"key1", "value1"})
      :ets.insert(:cache_table, {"key2", "value2"})

      assert :ok = Cache.clear()
      assert [] = :ets.tab2list(:cache_table)
    end
  end

  describe "get_and_update/2" do
    test "updates existing value" do
      key = "test_key"
      initial_value = "initial"
      updated_value = "updated"
      :ets.insert(:cache_table, {key, initial_value})

      assert {:ok, ^initial_value} =
               Cache.get_and_update(key, fn val ->
                 assert val == initial_value
                 {val, updated_value}
               end)

      assert [{^key, ^updated_value}] = :ets.lookup(:cache_table, key)
    end

    test "handles non-existing value" do
      key = "test_key"
      new_value = "new_value"

      assert {:ok, nil} =
               Cache.get_and_update(key, fn nil ->
                 {nil, new_value}
               end)

      assert [{^key, ^new_value}] = :ets.lookup(:cache_table, key)
    end
  end
end
