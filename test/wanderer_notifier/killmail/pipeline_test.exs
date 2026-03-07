defmodule WandererNotifier.Domains.Killmail.PipelineTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Domains.Killmail.Pipeline
  alias WandererNotifier.Test.Support.Helpers.ESIMockHelper
  alias WandererNotifier.Infrastructure.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Shared.Utils.TimeUtils

  # Define MockConfig for testing
  defmodule MockConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
    def deduplication_module, do: WandererNotifier.Domains.Notifications.Deduplication
    def system_track_module, do: WandererNotifier.MockSystem
    def character_track_module, do: WandererNotifier.MockCharacter
    def notification_determiner_module, do: WandererNotifier.Domains.Notifications.Determiner.Kill
    def killmail_enrichment_module, do: WandererNotifier.Domains.Killmail.Enrichment

    def killmail_notification_module,
      do: WandererNotifier.Domains.Notifications.KillmailNotification

    def config_module, do: __MODULE__
  end

  # Define MockCache for the tests
  defmodule MockCache do
    def get(key) do
      cond do
        key == CacheKeys.map_systems() ->
          {:ok, []}

        key == CacheKeys.map_characters() ->
          {:ok, [character_id: "100", name: "Victim"]}

        String.starts_with?(key, "tracked_character:") ->
          {:error, :not_found}

        true ->
          {:error, :not_found}
      end
    end

    def put(_key, _value), do: {:ok, :mock}
    def put(_key, _value, _ttl), do: {:ok, :mock}
    def delete(_key), do: {:ok, :mock}
    def clear(), do: {:ok, :mock}
    def get_and_update(_key, _fun), do: {:ok, :mock, :mock}
    def set(_key, _value, _opts), do: {:ok, :mock}
    def init_batch_logging(), do: :ok
  end

  # Use real deduplication implementation

  # Define MockMetrics for the tests
  defmodule MockMetrics do
    def track_processing_start(_), do: :ok
    def track_processing_end(_, _), do: :ok
    def track_error(_, _), do: :ok
    def track_notification_sent(_, _), do: :ok
    def track_skipped_notification(_, _), do: :ok
    def track_zkill_webhook_received(), do: :ok
    def track_zkill_processing_status(_, _), do: :ok
  end

  @test_map_slug "test-map"

  # Helper to register a system in the reverse index for tracking
  defp track_system(system_id) do
    WandererNotifier.Map.MapRegistry.index_system(@test_map_slug, to_string(system_id))
  end

  # Creates ETS tables if they don't exist (e.g. if MapRegistry GenServer was killed by another test).
  defp ensure_ets_table(table, type) do
    if :ets.info(table) == :undefined do
      :ets.new(table, [:named_table, type, :public, read_concurrency: true])
    end
  end

  # Helper to set up a test map config in the registry.
  defp ensure_test_map_config do
    ensure_ets_table(:map_registry_configs, :set)
    ensure_ets_table(:map_registry_system_index, :bag)
    ensure_ets_table(:map_registry_character_index, :bag)

    config = %WandererNotifier.Map.MapConfig{
      slug: @test_map_slug,
      name: "Test Map",
      map_id: @test_map_slug,
      owner: nil,
      discord: %{
        bot_token: nil,
        application_id: nil,
        guild_id: nil,
        channels: %{primary: "test-channel"},
        rally_group_ids: []
      },
      features: %{},
      settings: %{}
    }

    :ets.insert(:map_registry_configs, {@test_map_slug, config})
  end

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Ensure MapRegistry is running so reverse index ETS tables exist
    case WandererNotifier.Map.MapRegistry.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Ensure we use the real MapRegistry (not a mock from another test)
    Application.put_env(
      :wanderer_notifier,
      :map_registry_module,
      WandererNotifier.Map.MapRegistry
    )

    ensure_test_map_config()

    # Clear reverse index tables so tracked entries don't leak between tests
    if :ets.info(:map_registry_system_index) != :undefined do
      :ets.delete_all_objects(:map_registry_system_index)
    end

    if :ets.info(:map_registry_character_index) != :undefined do
      :ets.delete_all_objects(:map_registry_character_index)
    end

    # Ensure Cachex application is started
    case Application.ensure_all_started(:cachex) do
      {:ok, _apps} -> :ok
      {:error, _reason} -> :ok
    end

    # Use the correct cache name from config
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)

    # Start Cachex cache for tests - ignore if already started
    case Cachex.start_link(name: cache_name, limit: 1000) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      # Ignore other errors for test simplicity
      _ -> :ok
    end

    # Set up Mox for ESI.Service
    Application.put_env(
      :wanderer_notifier,
      :esi_service,
      WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
    )

    # Set up config module
    Application.put_env(:wanderer_notifier, :config, MockConfig)

    # Set up cache module and deduplication - use real implementation
    Application.put_env(:wanderer_notifier, :cache_repo, MockCache)

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Domains.Notifications.Deduplication
    )

    # Set up metrics module
    Application.put_env(:wanderer_notifier, :metrics, MockMetrics)

    # Set up WandererNotifier.HTTPMock
    Application.put_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HTTPMock
    )

    # Add stub for HTTPMock.request/5
    WandererNotifier.HTTPMock
    |> stub(:request, fn method, url, _body, _headers, _opts ->
      cond do
        method == :get and String.contains?(url, "killmails/12345/test_hash") ->
          {:ok,
           %{
             status_code: 200,
             body: %{
               "killmail_id" => 12_345,
               "victim" => %{
                 "character_id" => 100,
                 "corporation_id" => 300,
                 "ship_type_id" => 200
               },
               "killmail_time" => TimeUtils.log_timestamp(),
               "solar_system_id" => 30_000_142,
               "attackers" => []
             }
           }}

        method == :get and String.contains?(url, "killmails/54321/error_hash") ->
          {:error, :timeout}

        true ->
          {:ok, %{status_code: 404, body: %{"error" => "Not found"}}}
      end
    end)

    # Set up default stubs using the helper
    ESIMockHelper.setup_esi_mocks()

    # Always stub the DiscordNotifier with a default response
    stub(DiscordNotifierMock, :send_kill_notification, fn _killmail, _type, input_opts ->
      _formatted_opts = if is_map(input_opts), do: Map.to_list(input_opts), else: input_opts
      :ok
    end)

    :ok
  end

  describe "process_killmail/1" do
    test "process_killmail/1 successfully processes a valid killmail" do
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Set up tracking via reverse index
      track_system(30_000_142)

      # Execute the test - don't mock deduplication or Discord as they work in TEST MODE
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, _} = result
    end

    test "process_killmail/1 skips processing when notification is not needed" do
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # No tracked systems/characters in reverse index (default empty state)
      # Execute the test - should be skipped because neither system nor character is tracked
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, :skipped} = result
    end

    test "process_killmail/1 handles enrichment errors" do
      zkb_data = %{
        "killmail_id" => 54_321,
        "zkb" => %{"hash" => "error_hash"}
        # Missing system_id to trigger error
      }

      # Don't expect deduplication check since error happens before that
      # Execute the test - should error due to missing system_id
      result = Pipeline.process_killmail(zkb_data)
      assert {:error, :missing_system_id} = result
    end

    test "process_killmail/1 handles invalid payload" do
      # Missing killmail_id
      zkb_data = %{
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Execute the test - should error due to missing killmail_id
      result = Pipeline.process_killmail(zkb_data)
      assert {:error, :missing_killmail_id} = result
    end

    test "process_killmail/1 handles duplicate killmail" do
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Set up tracking and process once to create the deduplication entry
      track_system(30_000_142)
      Pipeline.process_killmail(zkb_data)

      # Now process again - this should be detected as duplicate
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, :skipped} = result
    end

    test "process_killmail/1 handles invalid system ID" do
      zkb_data = %{
        "killmail_id" => 99_999,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => "invalid"
      }

      # Don't expect deduplication check since error happens before that
      # Execute the test - should error due to invalid system_id parsing to nil
      result = Pipeline.process_killmail(zkb_data)
      assert {:error, :missing_system_id} = result
    end

    test "process_killmail/1 processes k-space kills when wormhole_only_kill_notifications is true (filtering at channel level)" do
      # Note: wormhole_only_kill_notifications filtering now happens at channel routing level
      # in DiscordNotifier, not at the pipeline level. K-space kills from tracked systems
      # are still processed, but excluded from the system kill channel.

      # Set config environment variables temporarily
      original_wormhole_value =
        Application.get_env(:wanderer_notifier, :wormhole_only_kill_notifications)

      original_suppression_value =
        Application.get_env(:wanderer_notifier, :startup_suppression_seconds)

      Application.put_env(:wanderer_notifier, :wormhole_only_kill_notifications, true)
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 78_910,
        "zkb" => %{"hash" => "kspace_hash", "totalValue" => 1_000_000},
        "solar_system_id" => 30_000_142,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 200,
          "ship_type_id" => 670
        },
        "attackers" => []
      }

      # Mark system as tracked via reverse index
      track_system(30_000_142)

      result = Pipeline.process_killmail(zkb_data)
      # Kill should be processed (not skipped) - channel filtering happens in DiscordNotifier
      assert {:ok, "78910"} = result

      # Restore original configs
      Application.put_env(
        :wanderer_notifier,
        :wormhole_only_kill_notifications,
        original_wormhole_value
      )

      Application.put_env(
        :wanderer_notifier,
        :startup_suppression_seconds,
        original_suppression_value
      )
    end

    test "process_killmail/1 allows wormhole kills when wormhole_only_kill_notifications is true" do
      # Set config environment variables temporarily
      original_wormhole_value =
        Application.get_env(:wanderer_notifier, :wormhole_only_kill_notifications)

      original_suppression_value =
        Application.get_env(:wanderer_notifier, :startup_suppression_seconds)

      Application.put_env(:wanderer_notifier, :wormhole_only_kill_notifications, true)
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 78_911,
        "zkb" => %{"hash" => "wh_hash", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 200,
          "ship_type_id" => 670
        },
        "attackers" => []
      }

      # Mark system as tracked via reverse index
      track_system(31_000_001)

      # Should process successfully since it's a wormhole system
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "78911"} = result

      # Restore original configs
      Application.put_env(
        :wanderer_notifier,
        :wormhole_only_kill_notifications,
        original_wormhole_value
      )

      Application.put_env(
        :wanderer_notifier,
        :startup_suppression_seconds,
        original_suppression_value
      )
    end

    test "process_killmail/1 processes all systems when wormhole_only_kill_notifications is false" do
      # Set config environment variables
      original_wormhole_value =
        Application.get_env(:wanderer_notifier, :wormhole_only_kill_notifications)

      original_suppression_value =
        Application.get_env(:wanderer_notifier, :startup_suppression_seconds)

      Application.put_env(:wanderer_notifier, :wormhole_only_kill_notifications, false)
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 78_912,
        "zkb" => %{"hash" => "kspace_hash2", "totalValue" => 1_000_000},
        "solar_system_id" => 30_000_142,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 200,
          "ship_type_id" => 670
        },
        "attackers" => []
      }

      # Mark system as tracked via reverse index
      track_system(30_000_142)

      # Should process successfully since wormhole_only flag is false
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "78912"} = result

      # Restore original configs
      Application.put_env(
        :wanderer_notifier,
        :wormhole_only_kill_notifications,
        original_wormhole_value
      )

      Application.put_env(
        :wanderer_notifier,
        :startup_suppression_seconds,
        original_suppression_value
      )
    end
  end

  describe "corporation exclusion" do
    # NOTE: Corporation exclusion is now handled at the Discord channel routing level
    # in DiscordNotifier, not in the pipeline. The pipeline processes all killmails
    # and exclusion only affects which Discord channels receive the notification.
    # These tests verify that the pipeline still processes killmails regardless of
    # corporation exclusion settings.

    setup do
      # Capture original config values before any test modifications
      original_kill_focus = Application.get_env(:wanderer_notifier, :corporation_kill_focus)
      original_suppression = Application.get_env(:wanderer_notifier, :startup_suppression_seconds)

      # Register cleanup to run even if test fails
      on_exit(fn ->
        Application.put_env(:wanderer_notifier, :corporation_kill_focus, original_kill_focus)

        Application.put_env(
          :wanderer_notifier,
          :startup_suppression_seconds,
          original_suppression
        )
      end)

      # Set up tracking via reverse index for all corp exclusion tests
      track_system(31_000_001)

      :ok
    end

    test "process_killmail/1 processes kills even when victim corporation is in exclusion list",
         _context do
      # Corporation exclusion now happens at Discord channel routing level, not pipeline
      # Set up exclusion list with victim's corporation
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [98_000_001])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_001,
        "zkb" => %{"hash" => "corp_exclude_hash1", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          # This corp is in exclusion list but pipeline still processes
          "corporation_id" => 98_000_001,
          "ship_type_id" => 670
        },
        "attackers" => [
          %{"character_id" => 200, "corporation_id" => 98_000_002}
        ]
      }

      # Pipeline should process the killmail - exclusion is handled at Discord level
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90001"} = result
    end

    test "process_killmail/1 processes kills even when attacker corporation is in exclusion list",
         _context do
      # Corporation exclusion now happens at Discord channel routing level, not pipeline
      # Set up exclusion list with attacker's corporation
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [98_000_002])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_002,
        "zkb" => %{"hash" => "corp_exclude_hash2", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 98_000_001,
          "ship_type_id" => 670
        },
        "attackers" => [
          # This corp is in exclusion list but pipeline still processes
          %{"character_id" => 200, "corporation_id" => 98_000_002}
        ]
      }

      # Pipeline should process the killmail - exclusion is handled at Discord level
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90002"} = result
    end

    test "process_killmail/1 allows kills when corporation is NOT in exclusion list", _context do
      # Set up exclusion list with different corporation
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [98_000_099])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_003,
        "zkb" => %{"hash" => "corp_exclude_hash3", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          # Not in exclusion list
          "corporation_id" => 98_000_001,
          "ship_type_id" => 670
        },
        "attackers" => [
          # Not in exclusion list
          %{"character_id" => 200, "corporation_id" => 98_000_002}
        ]
      }

      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90003"} = result
    end

    test "process_killmail/1 processes all kills when exclusion list is empty", _context do
      # Empty exclusion list
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_004,
        "zkb" => %{"hash" => "corp_exclude_hash4", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 98_000_001,
          "ship_type_id" => 670
        },
        "attackers" => []
      }

      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90004"} = result
    end

    test "process_killmail/1 processes kills even when any attacker in exclusion list matches",
         _context do
      # Corporation exclusion now happens at Discord channel routing level, not pipeline
      # Set up exclusion list
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [98_000_003])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_005,
        "zkb" => %{"hash" => "corp_exclude_hash5", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 98_000_001,
          "ship_type_id" => 670
        },
        "attackers" => [
          %{"character_id" => 200, "corporation_id" => 98_000_002},
          # Second attacker is in exclusion list but pipeline still processes
          %{"character_id" => 201, "corporation_id" => 98_000_003},
          %{"character_id" => 202, "corporation_id" => 98_000_004}
        ]
      }

      # Pipeline should process the killmail - exclusion is handled at Discord level
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90005"} = result
    end

    test "process_killmail/1 handles nil victim corporation_id gracefully", _context do
      # Set up exclusion list
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [98_000_001])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_006,
        "zkb" => %{"hash" => "corp_exclude_hash6", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          # No corporation_id - should not cause error
          "ship_type_id" => 670
        },
        "attackers" => [
          # Not in exclusion list
          %{"character_id" => 200, "corporation_id" => 98_000_002}
        ]
      }

      # Should process successfully - nil victim corp doesn't match exclusion
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90006"} = result
    end

    test "process_killmail/1 handles attackers with missing corporation_id gracefully",
         _context do
      # Set up exclusion list
      Application.put_env(:wanderer_notifier, :corporation_kill_focus, [98_000_001])
      Application.put_env(:wanderer_notifier, :startup_suppression_seconds, 0)

      zkb_data = %{
        "killmail_id" => 90_007,
        "zkb" => %{"hash" => "corp_exclude_hash7", "totalValue" => 1_000_000},
        "solar_system_id" => 31_000_001,
        "kill_time" => TimeUtils.to_iso8601(TimeUtils.now()),
        "victim" => %{
          "character_id" => 100,
          # Not in exclusion list
          "corporation_id" => 98_000_002,
          "ship_type_id" => 670
        },
        "attackers" => [
          # Attacker without corporation_id (NPC or structure)
          %{"character_id" => nil, "damage_done" => 1000},
          # Normal attacker not in exclusion list
          %{"character_id" => 200, "corporation_id" => 98_000_003}
        ]
      }

      # Should process successfully - attackers without corp_id are safely handled
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, "90007"} = result
    end
  end
end
