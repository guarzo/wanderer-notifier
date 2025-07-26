defmodule WandererNotifier.Domains.Tracking.Entities.CharacterTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Entities.Character
  alias WandererNotifier.Infrastructure.Cache

  import Mox

  setup :verify_on_exit!

  describe "new/1" do
    test "creates character from eve_id" do
      attrs = %{
        "eve_id" => "123456",
        "name" => "Test Character",
        "corporation_id" => 2001,
        "alliance_id" => 3001,
        "corporation_ticker" => "TEST",
        "alliance_ticker" => "ALLY"
      }

      character = Character.new(attrs)

      assert character.character_id == "123456"
      assert character.name == "Test Character"
      assert character.corporation_id == 2001
      assert character.alliance_id == 3001
      assert character.eve_id == "123456"
      assert character.corporation_ticker == "TEST"
      assert character.alliance_ticker == "ALLY"
      assert character.tracked == false
    end

    test "creates character from character_id" do
      attrs = %{
        "character_id" => "987654",
        "name" => "Another Character",
        "corporation_id" => 2002
      }

      character = Character.new(attrs)

      assert character.character_id == "987654"
      assert character.name == "Another Character"
      assert character.corporation_id == 2002
    end

    test "normalizes integer eve_id to string" do
      attrs = %{
        "eve_id" => 123_456,
        "name" => "Test Character"
      }

      character = Character.new(attrs)

      assert character.character_id == "123456"
      assert character.eve_id == 123_456
    end

    test "parses string corporation_id to integer" do
      attrs = %{
        "eve_id" => "123456",
        "name" => "Test Character",
        "corporation_id" => "2001"
      }

      character = Character.new(attrs)

      assert character.corporation_id == 2001
    end

    test "raises error when missing eve_id and character_id" do
      attrs = %{"name" => "Test Character"}

      assert_raise ArgumentError, ~r/Missing required character identification/, fn ->
        Character.new(attrs)
      end
    end

    test "raises error when missing name" do
      attrs = %{"eve_id" => "123456"}

      assert_raise ArgumentError, "Missing name for character", fn ->
        Character.new(attrs)
      end
    end

    test "handles nil values gracefully" do
      attrs = %{
        "eve_id" => "123456",
        "name" => "Test Character",
        "corporation_id" => nil,
        "alliance_id" => nil
      }

      character = Character.new(attrs)

      assert character.corporation_id == nil
      assert character.alliance_id == nil
    end
  end

  describe "new_safe/1" do
    test "returns {:ok, character} for valid data" do
      attrs = %{
        "eve_id" => "123456",
        "name" => "Test Character"
      }

      assert {:ok, character} = Character.new_safe(attrs)
      assert character.name == "Test Character"
    end

    test "returns {:error, reason} for invalid data" do
      attrs = %{"name" => "Test Character"}

      assert {:error, reason} = Character.new_safe(attrs)
      assert reason =~ "Missing required character identification"
    end
  end

  describe "Access behaviour" do
    setup do
      character =
        Character.new(%{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 2001,
          "corporation_ticker" => "TEST"
        })

      {:ok, character: character}
    end

    test "fetch/2 with atom keys", %{character: character} do
      assert {:ok, "Test Character"} = Character.fetch(character, :name)
      assert {:ok, "123456"} = Character.fetch(character, :character_id)
      assert :error = Character.fetch(character, :nonexistent)
    end

    test "fetch/2 with string keys", %{character: character} do
      assert {:ok, "123456"} = Character.fetch(character, "id")
      assert {:ok, 2001} = Character.fetch(character, "corporationID")
      assert {:ok, "TEST"} = Character.fetch(character, "corporationName")
    end

    test "fetch/2 with existing atom string keys", %{character: character} do
      assert {:ok, "Test Character"} = Character.fetch(character, "name")
      assert :error = Character.fetch(character, "nonexistent_key")
    end

    test "get/3 with default values", %{character: character} do
      assert "Test Character" = Character.get(character, :name)
      assert "default" = Character.get(character, :nonexistent, "default")
      assert nil = Character.get(character, :nonexistent)
    end

    test "get_and_update/3 raises not implemented", %{character: character} do
      assert_raise RuntimeError, "not implemented", fn ->
        Character.get_and_update(character, :name, fn x -> {x, "new"} end)
      end
    end

    test "pop/2 raises not implemented", %{character: character} do
      assert_raise RuntimeError, "not implemented", fn ->
        Character.pop(character, :name)
      end
    end
  end

  describe "has_corporation?/1" do
    test "returns true when both corporation_id and ticker are present" do
      character =
        Character.new(%{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 2001,
          "corporation_ticker" => "TEST"
        })

      assert Character.has_corporation?(character)
    end

    test "returns false when corporation_id is missing" do
      character =
        Character.new(%{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_ticker" => "TEST"
        })

      refute Character.has_corporation?(character)
    end

    test "returns false when corporation_ticker is missing" do
      character =
        Character.new(%{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 2001
        })

      refute Character.has_corporation?(character)
    end

    test "returns false for invalid input" do
      refute Character.has_corporation?(%{})
      refute Character.has_corporation?(nil)
    end
  end

  describe "is_tracked?/1" do
    test "returns true when character is in cached list" do
      characters = [
        %{"character_id" => "123456", "name" => "Test Character"},
        %{"character_id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      assert {:ok, true} = Character.is_tracked?("123456")
    end

    test "returns false when character is not in cached list" do
      characters = [
        %{"character_id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      assert {:ok, false} = Character.is_tracked?("123456")
    end

    test "returns false when cache is empty" do
      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:error, :not_found}
      end)

      assert {:ok, false} = Character.is_tracked?("123456")
    end

    test "handles integer character_id" do
      characters = [
        %{"character_id" => "123456", "name" => "Test Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      assert {:ok, true} = Character.is_tracked?(123_456)
    end

    test "returns error for invalid character_id" do
      assert {:error, :invalid_character_id} = Character.is_tracked?(nil)
      assert {:error, :invalid_character_id} = Character.is_tracked?(%{})
    end

    test "handles mixed key formats in cache" do
      characters = [
        %{:character_id => "123456", "name" => "Test Character"},
        %{"character_id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      assert {:ok, true} = Character.is_tracked?("123456")
    end
  end

  describe "get_character/1" do
    test "returns character when found in cache" do
      characters = [
        %{"id" => "123456", "name" => "Test Character"},
        %{"id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      character = Character.get_character("123456")
      assert character["name"] == "Test Character"
    end

    test "returns nil when character not found" do
      characters = [
        %{"id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      assert Character.get_character("123456") == nil
    end

    test "returns nil when cache is empty" do
      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:error, :not_found}
      end)

      assert Character.get_character("123456") == nil
    end
  end

  describe "get_character_by_name/1" do
    test "returns character when found by name" do
      characters = [
        %{"id" => "123456", "name" => "Test Character"},
        %{"id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      character = Character.get_character_by_name("Test Character")
      assert character["id"] == "123456"
    end

    test "returns nil when character name not found" do
      characters = [
        %{"id" => "789012", "name" => "Another Character"}
      ]

      expect(WandererNotifier.MockCache, :get, fn _key ->
        {:ok, characters}
      end)

      assert Character.get_character_by_name("Test Character") == nil
    end
  end
end
