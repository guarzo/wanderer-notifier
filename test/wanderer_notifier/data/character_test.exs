defmodule WandererNotifier.Data.CharacterTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Data.Character

  describe "new/1" do
    test "creates a character from map with standard fields" do
      map = %{
        "eve_id" => "12345",
        "name" => "Test Character",
        "corporation_id" => "67_890",
        "corporation_ticker" => "CORP",
        "alliance_id" => "54_321",
        "alliance_ticker" => "ALLY"
      }

      character = Character.new(map)

      assert %Character{} = character
      assert character.eve_id == "12345"
      assert character.name == "Test Character"
      assert character.corporation_id == 67_890
      assert character.corporation_ticker == "CORP"
      assert character.alliance_id == 54_321
      assert character.alliance_ticker == "ALLY"
      assert character.tracked == true
    end

    test "creates a character from nested character data" do
      map = %{
        "character" => %{
          "eve_id" => "12345",
          "name" => "Nested Character",
          "corporation_id" => "67_890",
          "corporation_ticker" => "CORP"
        }
      }

      character = Character.new(map)

      assert %Character{} = character
      assert character.eve_id == "12345"
      assert character.name == "Nested Character"
      assert character.corporation_id == 67_890
      assert character.corporation_ticker == "CORP"
      assert character.tracked == true
    end

    test "handles alternative field names" do
      map = %{
        "id" => "12345",
        "character_name" => "Alt Field Character",
        "corporationID" => "67_890",
        "corporation_name" => "CORP",
        "allianceID" => "54_321",
        "alliance_name" => "ALLY"
      }

      character = Character.new(map)

      assert %Character{} = character
      assert character.eve_id == "12345"
      assert character.name == "Alt Field Character"
      assert character.corporation_id == 67_890
      assert character.corporation_ticker == "CORP"
      assert character.alliance_id == 54_321
      assert character.alliance_ticker == "ALLY"
    end

    test "handles tracked field" do
      map = %{
        "eve_id" => "12345",
        "name" => "Untracked Character",
        "tracked" => false
      }

      character = Character.new(map)

      assert %Character{} = character
      assert character.tracked == false
    end

    test "raises error for missing required fields" do
      assert_raise ArgumentError, fn ->
        Character.new(%{"name" => "Missing ID"})
      end

      assert_raise ArgumentError, fn ->
        Character.new(%{"eve_id" => "12345"})
      end
    end

    test "raises error for invalid input type" do
      assert_raise ArgumentError, fn ->
        Character.new("not a map")
      end
    end
  end

  describe "from_map/1" do
    test "creates a character from map with exact field names" do
      map = %{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: "CORP",
        alliance_id: 54_321,
        alliance_ticker: "ALLY",
        tracked: false
      }

      character = Character.from_map(map)

      assert %Character{} = character
      assert character.eve_id == "12345"
      assert character.name == "Test Character"
      assert character.corporation_id == 67_890
      assert character.corporation_ticker == "CORP"
      assert character.alliance_id == 54_321
      assert character.alliance_ticker == "ALLY"
      assert character.tracked == false
    end

    test "raises error for missing required fields" do
      assert_raise ArgumentError, fn ->
        Character.from_map(%{name: "Missing ID"})
      end

      assert_raise ArgumentError, fn ->
        Character.from_map(%{eve_id: "12345"})
      end
    end
  end

  describe "Access behaviour" do
    setup do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: "CORP",
        alliance_id: 54_321,
        alliance_ticker: "ALLY",
        tracked: true
      }

      {:ok, character: character}
    end

    test "fetch/2 retrieves struct fields with atom keys", %{character: character} do
      assert {:ok, "12345"} = Character.fetch(character, :eve_id)
      assert {:ok, "Test Character"} = Character.fetch(character, :name)
      assert {:ok, 67_890} = Character.fetch(character, :corporation_id)
    end

    test "fetch/2 retrieves special field mappings with string keys", %{character: character} do
      assert {:ok, "12345"} = Character.fetch(character, "character_id")
      assert {:ok, "12345"} = Character.fetch(character, "id")
      assert {:ok, 67_890} = Character.fetch(character, "corporationID")
      assert {:ok, "CORP"} = Character.fetch(character, "corporationName")
      assert {:ok, 54_321} = Character.fetch(character, "allianceID")
      assert {:ok, "ALLY"} = Character.fetch(character, "allianceName")
    end

    test "fetch/2 returns error for non-existent keys", %{character: character} do
      assert :error = Character.fetch(character, :non_existent)
      assert :error = Character.fetch(character, "non_existent")
    end

    test "get/2 retrieves values with default", %{character: character} do
      assert Character.get(character, :eve_id) == "12345"
      assert Character.get(character, "character_id") == "12345"
      assert Character.get(character, :non_existent) == nil
      assert Character.get(character, :non_existent, "default") == "default"
    end

    test "get_and_update/3 raises error as not implemented", %{character: character} do
      assert_raise RuntimeError, ~r/get_and_update not implemented/, fn ->
        Character.get_and_update(character, :name, fn val -> {val, "New Name"} end)
      end
    end

    test "pop/2 raises error as not implemented", %{character: character} do
      assert_raise RuntimeError, ~r/pop not implemented/, fn ->
        Character.pop(character, :name)
      end
    end
  end

  describe "has_alliance?/1" do
    test "returns true when alliance data is present" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        alliance_id: 54_321,
        alliance_ticker: "ALLY"
      }

      assert Character.has_alliance?(character) == true
    end

    test "returns false when alliance data is missing" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        alliance_id: nil,
        alliance_ticker: nil
      }

      assert Character.has_alliance?(character) == false
    end

    test "returns false when alliance ticker is empty" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        alliance_id: 54_321,
        alliance_ticker: ""
      }

      assert Character.has_alliance?(character) == false
    end
  end

  describe "has_corporation?/1" do
    test "returns true when corporation data is present" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: "CORP"
      }

      assert Character.has_corporation?(character) == true
    end

    test "returns false when corporation data is missing" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: nil,
        corporation_ticker: nil
      }

      assert Character.has_corporation?(character) == false
    end

    test "returns false when corporation ticker is empty" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: ""
      }

      assert Character.has_corporation?(character) == false
    end
  end

  describe "format_name/1" do
    test "formats name with corporation and alliance" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: "CORP",
        alliance_id: 54_321,
        alliance_ticker: "ALLY"
      }

      assert Character.format_name(character) == "Test Character [CORP] <ALLY>"
    end

    test "formats name with corporation only" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: "CORP"
      }

      assert Character.format_name(character) == "Test Character [CORP]"
    end

    test "formats name with no corporation or alliance" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character"
      }

      assert Character.format_name(character) == "Test Character"
    end

    test "handles nil name" do
      character = %Character{
        eve_id: "12345",
        name: nil
      }

      assert Character.format_name(character) == "Unknown Character"
    end
  end

  describe "validate/1" do
    test "returns ok for valid character" do
      character = %Character{
        eve_id: "12345",
        name: "Test Character"
      }

      assert {:ok, ^character} = Character.validate(character)
    end

    test "returns error for missing eve_id" do
      character = %Character{
        eve_id: nil,
        name: "Test Character"
      }

      assert {:error, message} = Character.validate(character)
      assert message =~ "missing required eve_id"
    end

    test "returns error for missing name" do
      character = %Character{
        eve_id: "12345",
        name: nil
      }

      assert {:error, message} = Character.validate(character)
      assert message =~ "missing required name"
    end
  end
end
