defmodule WandererNotifier.Map.MapCharacterTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.MapCharacter

  describe "new/1" do
    test "creates a character from valid map data with nested character" do
      map_data = %{
        "character" => %{
          "name" => "Test Character",
          "corporation_id" => 123_456,
          "corporation_ticker" => "TEST",
          "alliance_id" => 789_012,
          "alliance_ticker" => "ALLI",
          "eve_id" => "1000001"
        },
        "tracked" => true
      }

      character = MapCharacter.new(map_data)

      assert %MapCharacter{} = character
      assert character.character_id == "1000001"
      assert character.name == "Test Character"
      assert character.corporation_id == 123_456
      assert character.corporation_ticker == "TEST"
      assert character.alliance_id == 789_012
      assert character.alliance_ticker == "ALLI"
      assert character.tracked == true
    end

    test "creates a character from valid map data with integer eve_id" do
      map_data = %{
        "character" => %{
          "name" => "Test Character",
          "corporation_id" => 123_456,
          "corporation_ticker" => "TEST",
          "alliance_id" => 789_012,
          "alliance_ticker" => "ALLI",
          "eve_id" => 1_000_001
        },
        "tracked" => true
      }

      character = MapCharacter.new(map_data)

      assert %MapCharacter{} = character
      assert character.character_id == "1000001"
    end

    test "falls back to character_id when eve_id is not present" do
      map_data = %{
        "character" => %{
          "name" => "Test Character",
          "corporation_id" => 123_456,
          "corporation_ticker" => "TEST"
        },
        "character_id" => "1000001",
        "tracked" => true
      }

      character = MapCharacter.new(map_data)

      assert %MapCharacter{} = character
      assert character.character_id == "1000001"
    end

    test "handles nil alliance_id and alliance_ticker" do
      map_data = %{
        "character" => %{
          "name" => "Test Character",
          "corporation_id" => 123_456,
          "corporation_ticker" => "TEST",
          "alliance_id" => nil,
          "alliance_ticker" => nil,
          "eve_id" => "1000001"
        },
        "tracked" => true
      }

      character = MapCharacter.new(map_data)

      assert %MapCharacter{} = character
      assert character.alliance_id == nil
      assert character.alliance_ticker == nil
    end

    test "raises ArgumentError when character_id is missing" do
      map_data = %{
        "character" => %{
          "name" => "Test Character"
        }
      }

      assert_raise ArgumentError, fn ->
        MapCharacter.new(map_data)
      end
    end

    test "raises ArgumentError when name is missing" do
      map_data = %{
        "character" => %{
          "eve_id" => "1000001"
        }
      }

      assert_raise ArgumentError, fn ->
        MapCharacter.new(map_data)
      end
    end

    test "converts corporation_id and alliance_id strings to integers" do
      map_data = %{
        "character" => %{
          "name" => "Test Character",
          "corporation_id" => "123456",
          "corporation_ticker" => "TEST",
          "alliance_id" => "789012",
          "alliance_ticker" => "ALLI",
          "eve_id" => "1000001"
        },
        "tracked" => true
      }

      character = MapCharacter.new(map_data)

      assert %MapCharacter{} = character
      assert is_integer(character.corporation_id)
      assert character.corporation_id == 123_456
      assert is_integer(character.alliance_id)
      assert character.alliance_id == 789_012
    end
  end

  describe "Access behavior" do
    setup do
      character = %MapCharacter{
        character_id: "1000001",
        name: "Test Character",
        corporation_id: 123_456,
        corporation_ticker: "TEST",
        alliance_id: 789_012,
        alliance_ticker: "ALLI",
        tracked: true
      }

      {:ok, %{character: character}}
    end

    test "fetch/2 with atom keys", %{character: character} do
      assert {:ok, "1000001"} = MapCharacter.fetch(character, :character_id)
      assert {:ok, "Test Character"} = MapCharacter.fetch(character, :name)
      assert {:ok, 123_456} = MapCharacter.fetch(character, :corporation_id)
      assert :error = MapCharacter.fetch(character, :nonexistent_field)
    end

    test "fetch/2 with string keys", %{character: character} do
      assert {:ok, "1000001"} = MapCharacter.fetch(character, "character_id")
      assert {:ok, "Test Character"} = MapCharacter.fetch(character, "name")
      assert {:ok, 123_456} = MapCharacter.fetch(character, "corporation_id")
      assert :error = MapCharacter.fetch(character, "nonexistent_field")
    end

    test "fetch/2 with special key mappings", %{character: character} do
      assert {:ok, "1000001"} = MapCharacter.fetch(character, "id")
      assert {:ok, 123_456} = MapCharacter.fetch(character, "corporationID")
      assert {:ok, "TEST"} = MapCharacter.fetch(character, "corporationName")
      assert {:ok, 789_012} = MapCharacter.fetch(character, "allianceID")
      assert {:ok, "ALLI"} = MapCharacter.fetch(character, "allianceName")
    end

    test "get/2 returns value or nil", %{character: character} do
      assert "1000001" = MapCharacter.get(character, :character_id)
      assert "Test Character" = MapCharacter.get(character, :name)
      assert nil == MapCharacter.get(character, :nonexistent_field)
    end

    test "get/3 returns value or default", %{character: character} do
      assert "1000001" = MapCharacter.get(character, :character_id, :default)
      assert "Test Character" = MapCharacter.get(character, :name, :default)
      assert :default == MapCharacter.get(character, :nonexistent_field, :default)
    end

    test "get_and_update/3 raises error", %{character: character} do
      assert_raise RuntimeError, fn ->
        MapCharacter.get_and_update(character, :name, fn _ -> {nil, "New Name"} end)
      end
    end

    test "pop/2 raises error", %{character: character} do
      assert_raise RuntimeError, fn ->
        MapCharacter.pop(character, :name)
      end
    end
  end

  describe "field access using Access notation" do
    setup do
      character = %MapCharacter{
        character_id: "1000001",
        name: "Test Character",
        corporation_id: 123_456,
        corporation_ticker: "TEST",
        alliance_id: 789_012,
        alliance_ticker: "ALLI",
        tracked: true
      }

      {:ok, %{character: character}}
    end

    test "allows access with map syntax", %{character: character} do
      assert character[:character_id] == "1000001"
      assert character["name"] == "Test Character"
      assert character[:nonexistent_field] == nil
      assert character["nonexistent_field"] == nil
    end

    test "allows access with special key mappings", %{character: character} do
      assert character["id"] == "1000001"
      assert character["corporationID"] == 123_456
      assert character["corporationName"] == "TEST"
      assert character["allianceID"] == 789_012
      assert character["allianceName"] == "ALLI"
    end
  end
end
