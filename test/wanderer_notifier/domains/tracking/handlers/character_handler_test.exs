defmodule WandererNotifier.Domains.Tracking.Handlers.CharacterHandlerTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Domains.Tracking.Handlers.CharacterHandler
  alias WandererNotifier.Infrastructure.Cache

  import ExUnit.CaptureLog
  import Mox
  import WandererNotifier.Test.Helpers.CacheTestHelper

  setup :verify_on_exit!

  setup do
    # Clear cache before each test
    "test-map" |> Cache.Keys.map_characters() |> Cache.delete()

    # Stub deduplication mock to allow notifications
    stub(WandererNotifier.MockDeduplication, :check, fn _type, _id -> {:ok, :new} end)

    # Stub ESI client mock for any notification formatting that might happen
    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_corporation_info, fn _id,
                                                                                            _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_alliance_info, fn _id,
                                                                                         _opts ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "ALLY"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_character_info, fn _id,
                                                                                          _opts ->
      {:ok, %{"name" => "Test Character"}}
    end)

    :ok
  end

  describe "handle_entity_removed/2" do
    test "removes character from cache when character exists" do
      # Setup: Add a character to the cache first
      existing_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 1000,
          "alliance_id" => 2000
        },
        %{
          "eve_id" => "789012",
          "name" => "Another Character",
          "corporation_id" => 1001,
          "alliance_id" => 2001
        }
      ]

      # Ensure cache operation succeeds and verify data was actually stored
      cache_key = Cache.Keys.map_characters("test-map")
      assert_cache_put(cache_key, existing_characters)

      # Create removal event
      event = %{
        "type" => "character_removed",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character"
        }
      }

      # Execute removal
      assert :ok = CharacterHandler.handle_entity_removed(event, "test-map")

      # Verify character was removed from cache
      {:ok, updated_characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(updated_characters) == 1
      assert hd(updated_characters)["eve_id"] == "789012"
      refute Enum.any?(updated_characters, fn c -> c["eve_id"] == "123456" end)
    end

    test "handles removal gracefully when character doesn't exist in cache" do
      # Setup: Add a different character to the cache
      existing_characters = [
        %{
          "eve_id" => "789012",
          "name" => "Another Character",
          "corporation_id" => 1001,
          "alliance_id" => 2001
        }
      ]

      cache_key = Cache.Keys.map_characters("test-map")
      assert_cache_put(cache_key, existing_characters)

      # Create removal event for non-existent character
      event = %{
        "type" => "character_removed",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Non-existent Character"
        }
      }

      # Execute removal
      assert :ok = CharacterHandler.handle_entity_removed(event, "test-map")

      # Verify cache is unchanged
      {:ok, updated_characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(updated_characters) == 1
      assert hd(updated_characters)["eve_id"] == "789012"
    end

    test "handles removal when cache is empty" do
      # Create removal event
      event = %{
        "type" => "character_removed",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character"
        }
      }

      # Execute removal
      assert :ok = CharacterHandler.handle_entity_removed(event, "test-map")

      # Verify cache is still empty/not found
      assert {:error, :not_found} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
    end

    test "removes all instances of character with same eve_id" do
      # Setup: Add duplicate characters (shouldn't happen but test defensive coding)
      existing_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 1000
        },
        %{
          "eve_id" => "789012",
          "name" => "Another Character",
          "corporation_id" => 1001
        },
        %{
          # Duplicate eve_id
          "eve_id" => "123456",
          "name" => "Test Character Duplicate",
          "corporation_id" => 1000
        }
      ]

      cache_key = Cache.Keys.map_characters("test-map")
      assert_cache_put(cache_key, existing_characters)

      # Create removal event
      event = %{
        "type" => "character_removed",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character"
        }
      }

      # Execute removal
      assert :ok = CharacterHandler.handle_entity_removed(event, "test-map")

      # Verify all instances with that eve_id were removed
      {:ok, updated_characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(updated_characters) == 1
      assert hd(updated_characters)["eve_id"] == "789012"
      refute Enum.any?(updated_characters, fn c -> c["eve_id"] == "123456" end)
    end

    test "logs character removal" do
      # Setup: Add a character to the cache
      existing_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 1000
        }
      ]

      cache_key = Cache.Keys.map_characters("test-map")
      assert_cache_put(cache_key, existing_characters)

      # Create removal event
      event = %{
        "type" => "character_removed",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character"
        }
      }

      # Execute removal and capture logs
      log_output =
        capture_log(fn ->
          assert :ok = CharacterHandler.handle_entity_removed(event, "test-map")
        end)

      assert log_output =~ "character_removed payload received"
      assert log_output =~ "Processing character_removed event"
      assert log_output =~ "Character removed from tracking"
    end
  end

  describe "handle_entity_added/2" do
    test "adds new character to empty cache" do
      event = %{
        "type" => "character_added",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 1000,
          "alliance_id" => 2000,
          "ship_type_id" => 670,
          "online" => true
        }
      }

      assert :ok = CharacterHandler.handle_entity_added(event, "test-map")

      {:ok, characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(characters) == 1

      character = hd(characters)
      assert character["eve_id"] == "123456"
      assert character["name"] == "Test Character"
      assert character["corporation_id"] == 1000
      assert character["alliance_id"] == 2000
      assert character["ship_type_id"] == 670
      assert character["online"] == true
    end

    test "doesn't add duplicate character with same eve_id" do
      # Setup: Add existing character
      existing_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 1000
        }
      ]

      cache_key = Cache.Keys.map_characters("test-map")
      assert_cache_put(cache_key, existing_characters)

      # Try to add same character again
      event = %{
        "type" => "character_added",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character Updated",
          "corporation_id" => 1001
        }
      }

      assert :ok = CharacterHandler.handle_entity_added(event, "test-map")

      # Verify only one character exists
      {:ok, characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(characters) == 1

      # Verify it's the original character (not updated)
      character = hd(characters)
      assert character["eve_id"] == "123456"
      # Original name
      assert character["name"] == "Test Character"
      # Original corp
      assert character["corporation_id"] == 1000
    end
  end

  describe "handle_entity_updated/2" do
    test "updates existing character by eve_id" do
      # Setup: Add existing character
      existing_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 1000,
          "online" => true,
          "ship_type_id" => 670
        }
      ]

      cache_key = Cache.Keys.map_characters("test-map")
      assert_cache_put(cache_key, existing_characters)

      # Update event
      event = %{
        "type" => "character_updated",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "Test Character",
          # Changed
          "corporation_id" => 1001,
          # Changed
          "online" => false,
          # Changed
          "ship_type_id" => 671
        }
      }

      assert :ok = CharacterHandler.handle_entity_updated(event, "test-map")

      # Verify character was updated
      {:ok, characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(characters) == 1

      character = hd(characters)
      assert character["eve_id"] == "123456"
      # Updated
      assert character["corporation_id"] == 1001
      # Updated
      assert character["online"] == false
      # Updated
      assert character["ship_type_id"] == 671
    end

    test "adds character if it doesn't exist during update" do
      # Update event for non-existent character
      event = %{
        "type" => "character_updated",
        "payload" => %{
          "id" => "char-1",
          "character_id" => "char-1",
          "eve_id" => "123456",
          "name" => "New Character",
          "corporation_id" => 1000,
          "online" => true
        }
      }

      assert :ok = CharacterHandler.handle_entity_updated(event, "test-map")

      # Verify character was added
      {:ok, characters} = "test-map" |> Cache.Keys.map_characters() |> Cache.get()
      assert length(characters) == 1

      character = hd(characters)
      assert character["eve_id"] == "123456"
      assert character["name"] == "New Character"
    end
  end
end
