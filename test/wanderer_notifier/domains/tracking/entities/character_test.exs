defmodule WandererNotifier.Domains.Tracking.Entities.CharacterTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Entities.Character
  alias WandererNotifier.Infrastructure.Cache

  setup do
    # Clear the cache before each test
    Cache.delete(Cache.Keys.map_characters())
    :ok
  end

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
      assert character.eve_id == "123456"
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

      assert_raise ArgumentError, "Character must have eve_id or character_id", fn ->
        Character.new(attrs)
      end
    end

    test "raises error when missing name" do
      attrs = %{"eve_id" => "123456"}

      assert_raise ArgumentError, "Character must have a name", fn ->
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

      assert {:error, {:validation_error, message}} = Character.new_safe(attrs)
      assert message == "Character must have eve_id or character_id"
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
  end

  describe "is_tracked?/1" do
    test "returns true when character is in cached list" do
      characters = [
        %{"eve_id" => "123456", "name" => "Test Character"},
        %{"eve_id" => "789012", "name" => "Another Character"}
      ]

      Cache.put(Cache.Keys.map_characters(), characters)

      assert {:ok, true} = Character.is_tracked?("123456")
    end

    test "returns false when character is not in cached list" do
      characters = [
        %{"eve_id" => "789012", "name" => "Another Character"}
      ]

      Cache.put(Cache.Keys.map_characters(), characters)

      assert {:ok, false} = Character.is_tracked?("123456")
    end

    test "returns false when cache is empty" do
      # Cache is already cleared in setup
      assert {:ok, false} = Character.is_tracked?("123456")
    end

    test "handles integer character_id" do
      characters = [
        %{"eve_id" => "123456", "name" => "Test Character"}
      ]

      Cache.put(Cache.Keys.map_characters(), characters)

      assert {:ok, true} = Character.is_tracked?(123_456)
    end

    test "returns error for invalid character_id" do
      assert {:error, :invalid_character_id} = Character.is_tracked?(nil)
      assert {:error, :invalid_character_id} = Character.is_tracked?(%{})
    end
  end

  describe "get_character/1" do
    test "returns character when found in cache" do
      characters = [
        %{"eve_id" => "123456", "name" => "Test Character"},
        %{"eve_id" => "789012", "name" => "Another Character"}
      ]

      Cache.put(Cache.Keys.map_characters(), characters)

      assert {:ok, character} = Character.get_character("123456")
      assert character.name == "Test Character"
    end

    test "returns error when character not found" do
      characters = [
        %{"eve_id" => "789012", "name" => "Another Character"}
      ]

      Cache.put(Cache.Keys.map_characters(), characters)

      assert {:error, :not_found} = Character.get_character("123456")
    end

    test "returns error when cache is empty" do
      # Cache is already cleared in setup
      assert {:error, :not_found} = Character.get_character("123456")
    end
  end
end
