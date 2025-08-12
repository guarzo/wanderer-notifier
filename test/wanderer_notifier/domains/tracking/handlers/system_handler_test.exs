defmodule WandererNotifier.Domains.Tracking.Handlers.SystemHandlerTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Handlers.SystemHandler
  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Infrastructure.Cache

  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!

  setup do
    # Clear cache before each test
    Cache.delete(Cache.Keys.map_systems())
    Cache.delete(Cache.Keys.tracked_systems_list())
    :ok
  end

  describe "handle_entity_removed/2" do
    test "removes system from both caches when system exists" do
      # Setup: Add systems to the cache first
      system1 = %System{
        solar_system_id: 30_000_142,
        name: "Jita",
        class_title: "High Sec",
        statics: [],
        region_name: "The Forge"
      }

      system2 = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        class_title: "C3",
        statics: ["D845"],
        region_name: "W-Space"
      }

      existing_systems = [system1, system2]
      Cache.put(Cache.Keys.map_systems(), existing_systems)

      # Also add to individual system cache
      Cache.put_tracked_system("31000001", %{
        "id" => 31_000_001,
        "name" => "J123456",
        "custom_name" => "Home",
        "class_title" => "C3"
      })

      # Create removal event
      event = %{
        "type" => "deleted_system",
        "payload" => %{
          "id" => 31_000_001
        }
      }

      # Execute removal
      assert :ok = SystemHandler.handle_entity_removed(event, "test-map")

      # Verify system was removed from main cache
      {:ok, updated_systems} = Cache.get(Cache.Keys.map_systems())
      assert length(updated_systems) == 1
      assert hd(updated_systems).solar_system_id == 30_000_142
      refute Enum.any?(updated_systems, fn s -> s.solar_system_id == 31_000_001 end)

      # Verify individual system cache was also deleted
      assert {:error, :not_found} = Cache.get_tracked_system("31000001")
    end

    test "handles removal gracefully when system doesn't exist in cache" do
      # Setup: Add a different system to the cache
      system1 = %System{
        solar_system_id: 30_000_142,
        name: "Jita",
        class_title: "High Sec",
        statics: [],
        region_name: "The Forge"
      }

      Cache.put(Cache.Keys.map_systems(), [system1])

      # Create removal event for non-existent system
      event = %{
        "type" => "deleted_system",
        "payload" => %{
          "id" => 31_000_001
        }
      }

      # Execute removal
      assert :ok = SystemHandler.handle_entity_removed(event, "test-map")

      # Verify cache is unchanged
      {:ok, updated_systems} = Cache.get(Cache.Keys.map_systems())
      assert length(updated_systems) == 1
      assert hd(updated_systems).solar_system_id == 30_000_142
    end

    test "handles removal when cache is empty" do
      # Create removal event
      event = %{
        "type" => "deleted_system",
        "payload" => %{
          "id" => 31_000_001
        }
      }

      # Execute removal
      assert :ok = SystemHandler.handle_entity_removed(event, "test-map")

      # Verify cache returns nil/empty
      result = Cache.get(Cache.Keys.map_systems())
      assert result == {:ok, nil} or result == {:error, :not_found}
    end

    test "removes system with different id field variations" do
      # Test that we handle different ways the system ID might be stored
      system_with_id = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        class_title: "C3"
      }

      # Also test with plain maps that might exist in cache
      map_with_solar_system_id = %{
        "solar_system_id" => 31_000_002,
        "name" => "J234567"
      }

      map_with_id = %{
        "id" => 31_000_003,
        "name" => "J345678"
      }

      existing_systems = [system_with_id, map_with_solar_system_id, map_with_id]
      Cache.put(Cache.Keys.map_systems(), existing_systems)

      # Test removal by system ID
      event1 = %{
        "type" => "deleted_system",
        "payload" => %{"id" => 31_000_001}
      }

      assert :ok = SystemHandler.handle_entity_removed(event1, "test-map")

      {:ok, updated_systems} = Cache.get(Cache.Keys.map_systems())
      assert length(updated_systems) == 2

      refute Enum.any?(updated_systems, fn s ->
               (is_struct(s, System) && s.solar_system_id == 31_000_001) ||
                 (is_map(s) && Map.get(s, "solar_system_id") == 31_000_001)
             end)
    end

    test "logs system removal" do
      # Setup: Add a system to cache
      system = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        class_title: "C3"
      }

      Cache.put(Cache.Keys.map_systems(), [system])
      Cache.put_tracked_system("31000001", %{"id" => 31_000_001, "name" => "J123456"})

      # Create removal event
      event = %{
        "type" => "deleted_system",
        "payload" => %{
          "id" => 31_000_001
        }
      }

      # Execute removal and capture logs
      log_output =
        capture_log(fn ->
          assert :ok = SystemHandler.handle_entity_removed(event, "test-map")
        end)

      assert log_output =~ "system_removed payload received"
      assert log_output =~ "Processing system_removed event"
      assert log_output =~ "System removed from tracking"
      assert log_output =~ "31000001"
    end

    test "removes individual system cache entry even if main cache fails" do
      # Don't add to main cache, but add individual entry
      Cache.put_tracked_system("31000001", %{
        "id" => 31_000_001,
        "name" => "J123456",
        "custom_name" => "Home"
      })

      # Create removal event
      event = %{
        "type" => "deleted_system",
        "payload" => %{
          "id" => 31_000_001
        }
      }

      # Execute removal
      assert :ok = SystemHandler.handle_entity_removed(event, "test-map")

      # Verify individual cache was deleted
      assert {:error, :not_found} = Cache.get_tracked_system("31000001")
    end
  end

  describe "handle_entity_added/2" do
    test "adds new system to cache and enriches it" do
      event = %{
        "type" => "add_system",
        "payload" => %{
          "id" => 31_000_001,
          "name" => "J123456",
          "solar_system_id" => 31_000_001,
          "custom_name" => "Home System",
          "description" => "Our main base"
        }
      }

      assert :ok = SystemHandler.handle_entity_added(event, "test-map")

      # Check main systems cache
      {:ok, systems} = Cache.get(Cache.Keys.map_systems())
      assert length(systems) == 1

      system = hd(systems)
      assert system.solar_system_id == 31_000_001
      assert system.name == "J123456"
      # Should be enriched with static data
      assert system.class_title != nil

      # Check individual system cache
      {:ok, cached_system} = Cache.get_tracked_system("31000001")
      assert cached_system["id"] == 31_000_001
      assert cached_system["custom_name"] == "Home System"
      assert cached_system["description"] == "Our main base"
    end

    test "updates existing system instead of duplicating" do
      # Setup: Add existing system
      existing_system = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        class_title: "C3",
        statics: ["D845"]
      }

      Cache.put(Cache.Keys.map_systems(), [existing_system])

      # Try to add same system again with updated data
      event = %{
        "type" => "add_system",
        "payload" => %{
          "id" => 31_000_001,
          "name" => "J123456",
          "solar_system_id" => 31_000_001,
          "custom_name" => "Updated Home"
        }
      }

      assert :ok = SystemHandler.handle_entity_added(event, "test-map")

      # Verify only one system exists
      {:ok, systems} = Cache.get(Cache.Keys.map_systems())
      assert length(systems) == 1

      # Check individual cache has updated custom_name
      {:ok, cached_system} = Cache.get_tracked_system("31000001")
      assert cached_system["custom_name"] == "Updated Home"
    end
  end

  describe "handle_entity_updated/2" do
    test "updates system metadata" do
      # Setup: Add existing system
      existing_system = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        class_title: "C3",
        statics: ["D845"]
      }

      Cache.put(Cache.Keys.map_systems(), [existing_system])

      Cache.put_tracked_system("31000001", %{
        "id" => 31_000_001,
        "custom_name" => "Old Name"
      })

      # Update event
      event = %{
        "type" => "system_metadata_changed",
        "payload" => %{
          "id" => 31_000_001,
          "name" => "J123456",
          "solar_system_id" => 31_000_001,
          "custom_name" => "New Name",
          "description" => "Updated description"
        }
      }

      assert :ok = SystemHandler.handle_entity_updated(event, "test-map")

      # Verify system still exists in main cache
      {:ok, systems} = Cache.get(Cache.Keys.map_systems())
      assert length(systems) == 1

      # Verify individual cache was updated
      {:ok, cached_system} = Cache.get_tracked_system("31000001")
      assert cached_system["custom_name"] == "New Name"
      assert cached_system["description"] == "Updated description"
    end

    test "adds system if it doesn't exist during update" do
      # Update event for non-existent system
      event = %{
        "type" => "system_metadata_changed",
        "payload" => %{
          "id" => 31_000_001,
          "name" => "J123456",
          "solar_system_id" => 31_000_001,
          "custom_name" => "New System"
        }
      }

      assert :ok = SystemHandler.handle_entity_updated(event, "test-map")

      # Verify system was added
      {:ok, systems} = Cache.get(Cache.Keys.map_systems())
      assert length(systems) == 1

      system = hd(systems)
      assert system.solar_system_id == 31_000_001

      # Verify individual cache was created
      {:ok, cached_system} = Cache.get_tracked_system("31000001")
      assert cached_system["custom_name"] == "New System"
    end
  end
end
