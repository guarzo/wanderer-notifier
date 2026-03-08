defmodule WandererNotifier.Domains.Killmail.PipelineTrackingTest do
  @moduledoc """
  Tests for the diagnostic logging in Pipeline when a kill is not tracked.

  The key functions under test are `log_tracking_cache_state/1` and
  `tracking_counts_by_mode/1`, which are private. We exercise them
  indirectly by verifying the mock wiring that Pipeline relies on
  (Dependencies.map_registry/0) and, where feasible, by capturing log
  output through the public `process_killmail/1` entry point.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox

  alias WandererNotifier.Infrastructure.Cache.Keys, as: CacheKeys

  setup :verify_on_exit!

  # ---------------------------------------------------------------------------
  # Setup / teardown
  # ---------------------------------------------------------------------------

  setup do
    original = Application.get_env(:wanderer_notifier, :map_registry_module)

    on_exit(fn ->
      if original do
        Application.put_env(:wanderer_notifier, :map_registry_module, original)
      else
        Application.delete_env(:wanderer_notifier, :map_registry_module)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "tracking diagnostics" do
    test "api mode registry exposes expected interface" do
      mock = WandererNotifier.MockMapRegistry

      stub(mock, :mode, fn -> :api end)
      stub(mock, :tracking_index_counts, fn -> {5, 3} end)

      Application.put_env(:wanderer_notifier, :map_registry_module, mock)

      registry = Application.get_env(:wanderer_notifier, :map_registry_module)

      assert registry.mode() == :api
      assert registry.tracking_index_counts() == {5, 3}
    end

    test "env_var mode registry exposes expected interface" do
      mock = WandererNotifier.MockMapRegistry

      stub(mock, :mode, fn -> :env_var end)
      stub(mock, :tracking_index_counts, fn -> {0, 0} end)

      Application.put_env(:wanderer_notifier, :map_registry_module, mock)

      registry = Application.get_env(:wanderer_notifier, :map_registry_module)

      assert registry.mode() == :env_var
      assert registry.tracking_index_counts() == {0, 0}
    end

    test "api mode registry returns empty lists for system/character lookups" do
      mock = WandererNotifier.MockMapRegistry

      stub(mock, :maps_tracking_system, fn _ -> [] end)
      stub(mock, :maps_tracking_character, fn _ -> [] end)

      Application.put_env(:wanderer_notifier, :map_registry_module, mock)

      registry = Application.get_env(:wanderer_notifier, :map_registry_module)

      assert registry.maps_tracking_system("31000001") == []
      assert registry.maps_tracking_character("12345") == []
    end

    test "env_var mode cache keys resolve to expected strings" do
      # Verify the cache keys used in env_var mode
      assert CacheKeys.map_systems() == "map:systems"
      assert CacheKeys.map_characters() == "map:characters"
    end

    test "Dependencies.map_registry/0 respects application env override" do
      mock = WandererNotifier.MockMapRegistry

      stub(mock, :mode, fn -> :api end)

      Application.put_env(:wanderer_notifier, :map_registry_module, mock)

      resolved = WandererNotifier.Shared.Dependencies.map_registry()
      assert resolved == mock
      assert resolved.mode() == :api
    end

    test "Dependencies.map_registry/0 falls back to default when env cleared" do
      Application.delete_env(:wanderer_notifier, :map_registry_module)

      resolved = WandererNotifier.Shared.Dependencies.map_registry()
      assert resolved == WandererNotifier.Map.MapRegistry
    end
  end

  describe "tracking log format via process_killmail" do
    # Processing a killmail through the full pipeline requires significant
    # mocking infrastructure (dedup, config, ESI, HTTP, metrics, etc.).
    # These tests set up the minimum viable mocking to reach the
    # `handle_non_tracked_killmail` code path and verify the log output.

    setup do
      # Ensure Cachex is available
      cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)

      case Cachex.start_link(name: cache_name, limit: 1000) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        _ -> :ok
      end

      :ok
    end

    test "logs mode=api with index counts when killmail is not tracked" do
      mock = WandererNotifier.MockMapRegistry

      stub(mock, :mode, fn -> :api end)
      stub(mock, :tracking_index_counts, fn -> {5, 3} end)
      stub(mock, :maps_tracking_system, fn _ -> [] end)
      stub(mock, :maps_tracking_character, fn _ -> [] end)

      # Stub ESI service so build_killmail can resolve system name
      stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system, fn id, _opts ->
        {:ok, %{"name" => "System-#{id}", "system_id" => id}}
      end)

      Application.put_env(:wanderer_notifier, :map_registry_module, mock)

      # Build a minimal killmail payload that will pass ID extraction
      # but fail should_notify? (no tracked systems/characters)
      killmail_data = %{
        "killmail_id" => 99_999_001,
        "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 1_000_001,
          "corporation_id" => 2_000_001,
          "ship_type_id" => 587,
          "items" => []
        },
        "attackers" => [
          %{
            "character_id" => 1_000_002,
            "corporation_id" => 2_000_002,
            "ship_type_id" => 24_690,
            "final_blow" => true,
            "damage_done" => 1000,
            "weapon_type_id" => 3170
          }
        ],
        "zkb" => %{
          "totalValue" => 10_000_000,
          "hash" => "abc123"
        }
      }

      log_output =
        capture_log([level: :warning], fn ->
          WandererNotifier.Domains.Killmail.Pipeline.process_killmail(killmail_data)
        end)

      assert String.contains?(log_output, "NOT TRACKED"),
             "Expected 'NOT TRACKED' diagnostic log but got: #{log_output}"

      assert String.contains?(log_output, "mode=api")
      assert String.contains?(log_output, "5 system")
      assert String.contains?(log_output, "3 character")
      assert String.contains?(log_output, "cross-map duplicates")
    end

    test "logs mode=env_var when using env_var mode registry" do
      mock = WandererNotifier.MockMapRegistry

      stub(mock, :mode, fn -> :env_var end)
      stub(mock, :tracking_index_counts, fn -> {0, 0} end)
      stub(mock, :maps_tracking_system, fn _ -> [] end)
      stub(mock, :maps_tracking_character, fn _ -> [] end)

      # Stub ESI service so build_killmail can resolve system name
      stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system, fn id, _opts ->
        {:ok, %{"name" => "System-#{id}", "system_id" => id}}
      end)

      Application.put_env(:wanderer_notifier, :map_registry_module, mock)

      killmail_data = %{
        "killmail_id" => 99_999_002,
        "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 1_000_001,
          "corporation_id" => 2_000_001,
          "ship_type_id" => 587,
          "items" => []
        },
        "attackers" => [
          %{
            "character_id" => 1_000_002,
            "corporation_id" => 2_000_002,
            "ship_type_id" => 24_690,
            "final_blow" => true,
            "damage_done" => 1000,
            "weapon_type_id" => 3170
          }
        ],
        "zkb" => %{
          "totalValue" => 10_000_000,
          "hash" => "def456"
        }
      }

      log_output =
        capture_log([level: :warning], fn ->
          WandererNotifier.Domains.Killmail.Pipeline.process_killmail(killmail_data)
        end)

      assert String.contains?(log_output, "NOT TRACKED"),
             "Expected 'NOT TRACKED' diagnostic log but got: #{log_output}"

      assert String.contains?(log_output, "mode=env_var")
      assert String.contains?(log_output, "0 system")
      assert String.contains?(log_output, "0 character")
    end
  end
end
