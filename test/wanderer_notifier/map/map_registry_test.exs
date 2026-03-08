defmodule WandererNotifier.Map.MapRegistryTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Map.MapRegistry

  @configs_table :map_registry_configs
  @system_index_table :map_registry_system_index
  @character_index_table :map_registry_character_index

  setup do
    # Create (or recreate) the 3 ETS tables that MapRegistry normally owns
    tables = [
      {@configs_table, [:named_table, :set, :public, read_concurrency: true]},
      {@system_index_table, [:named_table, :bag, :public, read_concurrency: true]},
      {@character_index_table, [:named_table, :bag, :public, read_concurrency: true]}
    ]

    for {name, opts} <- tables do
      if :ets.whereis(name) != :undefined do
        :ets.delete(name)
      end

      :ets.new(name, opts)
    end

    # Set the mode persistent_term to :api
    :persistent_term.put({MapRegistry, :mode}, :api)

    on_exit(fn ->
      # Restore mode to :env_var so other tests aren't affected
      :persistent_term.erase({MapRegistry, :mode})

      for {name, _opts} <- tables do
        if :ets.whereis(name) != :undefined do
          :ets.delete(name)
        end
      end
    end)

    :ok
  end

  describe "tracking_index_counts/0" do
    test "returns {0, 0} for empty tables" do
      assert MapRegistry.tracking_index_counts() == {0, 0}
    end

    test "returns correct counts after inserting entries" do
      :ets.insert(@system_index_table, {"31000001", "map-a"})
      :ets.insert(@system_index_table, {"31000002", "map-a"})
      :ets.insert(@system_index_table, {"31000003", "map-b"})

      :ets.insert(@character_index_table, {"12345", "map-a"})
      :ets.insert(@character_index_table, {"67890", "map-b"})

      assert MapRegistry.tracking_index_counts() == {3, 2}
    end

    test "counts bag duplicates (same key, different slugs)" do
      :ets.insert(@system_index_table, {"31000001", "map-a"})
      :ets.insert(@system_index_table, {"31000001", "map-b"})

      {system_count, _character_count} = MapRegistry.tracking_index_counts()
      assert system_count == 2
    end
  end

  describe "mode/0" do
    test "returns :api when set" do
      assert MapRegistry.mode() == :api
    end

    test "defaults to :env_var" do
      :persistent_term.erase({MapRegistry, :mode})
      assert MapRegistry.mode() == :env_var

      # Restore for other tests
      :persistent_term.put({MapRegistry, :mode}, :api)
    end
  end
end
