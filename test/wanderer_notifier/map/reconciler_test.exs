defmodule WandererNotifier.Map.ReconcilerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias WandererNotifier.Map.MapConfig
  alias WandererNotifier.Map.Reconciler

  setup :verify_on_exit!

  @map_slug "test-slug"

  defp build_map_config do
    %MapConfig{
      slug: @map_slug,
      name: "Test Map",
      map_id: "test-map-id"
    }
  end

  describe "reconcile_map/2" do
    test "deindexes systems that are no longer in the fresh upstream list" do
      test_pid = self()
      mock_registry = WandererNotifier.MockMapRegistry

      stub(mock_registry, :systems_for_map, fn _slug -> ["31000001", "31000002", "31000003"] end)

      stub(mock_registry, :deindex_system, fn slug, system_id ->
        send(test_pid, {:deindex, slug, system_id})
        :ok
      end)

      fetch_fun = fn _map_config ->
        {:ok,
         [
           %{"solar_system_id" => 31_000_001, "name" => "A"},
           %{"solar_system_id" => 31_000_002, "name" => "B"}
         ]}
      end

      assert {:ok, :reconciled} =
               Reconciler.reconcile_map(build_map_config(),
                 registry: mock_registry,
                 fetch_fun: fetch_fun
               )

      # 31000003 is stale — it must be deindexed
      assert_received {:deindex, @map_slug, "31000003"}
      # The other two remain — must not be deindexed
      refute_received {:deindex, @map_slug, "31000001"}
      refute_received {:deindex, @map_slug, "31000002"}
    end

    test "leaves state unchanged when upstream returns an empty list" do
      test_pid = self()
      mock_registry = WandererNotifier.MockMapRegistry

      stub(mock_registry, :systems_for_map, fn _slug -> ["31000001"] end)

      stub(mock_registry, :deindex_system, fn slug, system_id ->
        send(test_pid, {:deindex, slug, system_id})
        :ok
      end)

      fetch_fun = fn _map_config -> {:ok, []} end

      log =
        capture_log(fn ->
          assert {:ok, :skipped_empty} =
                   Reconciler.reconcile_map(build_map_config(),
                     registry: mock_registry,
                     fetch_fun: fetch_fun
                   )
        end)

      refute_received {:deindex, _, _}
      assert log =~ "empty system list"
    end

    test "leaves state unchanged when upstream returns an error" do
      test_pid = self()
      mock_registry = WandererNotifier.MockMapRegistry

      stub(mock_registry, :systems_for_map, fn _slug -> ["31000001", "31000002"] end)

      stub(mock_registry, :deindex_system, fn slug, system_id ->
        send(test_pid, {:deindex, slug, system_id})
        :ok
      end)

      fetch_fun = fn _map_config -> {:error, {:http_error, 503}} end

      log =
        capture_log(fn ->
          assert {:error, {:http_error, 503}} =
                   Reconciler.reconcile_map(build_map_config(),
                     registry: mock_registry,
                     fetch_fun: fetch_fun
                   )
        end)

      refute_received {:deindex, _, _}
      assert log =~ "fetch failed"
    end

    test "is a no-op when no systems are stale" do
      test_pid = self()
      mock_registry = WandererNotifier.MockMapRegistry

      stub(mock_registry, :systems_for_map, fn _slug -> ["31000001"] end)

      stub(mock_registry, :deindex_system, fn slug, system_id ->
        send(test_pid, {:deindex, slug, system_id})
        :ok
      end)

      fetch_fun = fn _map_config -> {:ok, [%{"solar_system_id" => 31_000_001}]} end

      assert {:ok, :reconciled} =
               Reconciler.reconcile_map(build_map_config(),
                 registry: mock_registry,
                 fetch_fun: fetch_fun
               )

      refute_received {:deindex, _, _}
    end

    test "accepts fresh systems with string solar_system_id" do
      test_pid = self()
      mock_registry = WandererNotifier.MockMapRegistry

      stub(mock_registry, :systems_for_map, fn _slug -> ["31000001", "31000002"] end)

      stub(mock_registry, :deindex_system, fn slug, system_id ->
        send(test_pid, {:deindex, slug, system_id})
        :ok
      end)

      # Production payload sometimes ships ids as strings
      fetch_fun = fn _map_config ->
        {:ok, [%{"solar_system_id" => "31000001"}]}
      end

      assert {:ok, :reconciled} =
               Reconciler.reconcile_map(build_map_config(),
                 registry: mock_registry,
                 fetch_fun: fetch_fun
               )

      # 31000001 is still present (even as string) — must not be deindexed
      refute_received {:deindex, @map_slug, "31000001"}
      # 31000002 is stale
      assert_received {:deindex, @map_slug, "31000002"}
    end

    test "ignores fresh systems without a parseable solar_system_id" do
      test_pid = self()
      mock_registry = WandererNotifier.MockMapRegistry

      stub(mock_registry, :systems_for_map, fn _slug -> ["31000001"] end)

      stub(mock_registry, :deindex_system, fn slug, system_id ->
        send(test_pid, {:deindex, slug, system_id})
        :ok
      end)

      # Malformed entry with no resolvable id — should not cause 31000001 to be
      # incorrectly considered stale
      fetch_fun = fn _map_config ->
        {:ok,
         [
           %{"solar_system_id" => 31_000_001},
           %{"name" => "No id at all"}
         ]}
      end

      assert {:ok, :reconciled} =
               Reconciler.reconcile_map(build_map_config(),
                 registry: mock_registry,
                 fetch_fun: fetch_fun
               )

      refute_received {:deindex, _, _}
    end
  end
end
