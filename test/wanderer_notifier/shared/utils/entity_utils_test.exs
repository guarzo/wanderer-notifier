defmodule WandererNotifier.Shared.Utils.EntityUtilsTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Shared.Utils.EntityUtils

  describe "extract_system_id/1" do
    test "extracts from struct with various field names" do
      assert EntityUtils.extract_system_id(%{solar_system_id: 30_000_142}) == 30_000_142
      assert EntityUtils.extract_system_id(%{system_id: 30_000_142}) == 30_000_142
      assert EntityUtils.extract_system_id(%{id: 30_000_142}) == 30_000_142
    end

    test "extracts from map with string keys" do
      assert EntityUtils.extract_system_id(%{"solar_system_id" => 30_000_142}) == 30_000_142
      assert EntityUtils.extract_system_id(%{"system_id" => "30000142"}) == 30_000_142
    end

    test "extracts from map with atom keys" do
      assert EntityUtils.extract_system_id(%{solar_system_id: "30000142"}) == 30_000_142
      assert EntityUtils.extract_system_id(%{system_id: 30_000_142}) == 30_000_142
    end

    test "returns nil for invalid input" do
      assert EntityUtils.extract_system_id(nil) == nil
      assert EntityUtils.extract_system_id("not a map") == nil
      assert EntityUtils.extract_system_id(%{}) == nil
      assert EntityUtils.extract_system_id(%{"system_id" => "invalid"}) == nil
    end
  end

  describe "valid_system_id?/1" do
    test "validates correct system IDs" do
      assert EntityUtils.valid_system_id?(30_000_142) == true
      assert EntityUtils.valid_system_id?(30_000_001) == true
      assert EntityUtils.valid_system_id?(39_999_999) == true
    end

    test "rejects invalid system IDs" do
      assert EntityUtils.valid_system_id?(29_999_999) == false
      assert EntityUtils.valid_system_id?(40_000_001) == false
      assert EntityUtils.valid_system_id?(nil) == false
      assert EntityUtils.valid_system_id?("30000142") == false
    end
  end

  describe "extract_character_id/1" do
    test "extracts from nested character structure" do
      assert EntityUtils.extract_character_id(%{"character" => %{"eve_id" => 95_123_456}}) ==
               95_123_456

      assert EntityUtils.extract_character_id(%{"character" => %{"eve_id" => "95123456"}}) ==
               95_123_456
    end

    test "extracts from flat structure" do
      assert EntityUtils.extract_character_id(%{character_id: 95_123_456}) == 95_123_456
      assert EntityUtils.extract_character_id(%{"character_id" => "95123456"}) == 95_123_456
      assert EntityUtils.extract_character_id(%{eve_id: 95_123_456}) == 95_123_456
    end

    test "returns nil for invalid input" do
      assert EntityUtils.extract_character_id(nil) == nil
      assert EntityUtils.extract_character_id(%{}) == nil
      assert EntityUtils.extract_character_id(%{"character_id" => "invalid"}) == nil
    end
  end

  describe "valid_character_id?/1" do
    test "validates correct character IDs" do
      assert EntityUtils.valid_character_id?(95_123_456) == true
      assert EntityUtils.valid_character_id?(90_000_001) == true
      assert EntityUtils.valid_character_id?(99_999_999_999) == true
    end

    test "rejects invalid character IDs" do
      assert EntityUtils.valid_character_id?(89_999_999) == false
      assert EntityUtils.valid_character_id?(100_000_000_001) == false
      assert EntityUtils.valid_character_id?(nil) == false
      assert EntityUtils.valid_character_id?("95123456") == false
    end
  end

  describe "extract_corporation_id/1" do
    test "extracts corporation ID from various formats" do
      assert EntityUtils.extract_corporation_id(%{corporation_id: 98_123_456}) == 98_123_456
      assert EntityUtils.extract_corporation_id(%{"corporation_id" => "98123456"}) == 98_123_456
      assert EntityUtils.extract_corporation_id(%{corp_id: 98_123_456}) == 98_123_456
    end

    test "returns nil for invalid input" do
      assert EntityUtils.extract_corporation_id(nil) == nil
      assert EntityUtils.extract_corporation_id(%{}) == nil
    end
  end

  describe "valid_corporation_id?/1" do
    test "validates correct corporation IDs" do
      assert EntityUtils.valid_corporation_id?(98_123_456) == true
      assert EntityUtils.valid_corporation_id?(98_000_000) == true
      assert EntityUtils.valid_corporation_id?(98_999_999) == true
    end

    test "rejects invalid corporation IDs" do
      assert EntityUtils.valid_corporation_id?(97_999_999) == false
      assert EntityUtils.valid_corporation_id?(99_000_001) == false
      assert EntityUtils.valid_corporation_id?(nil) == false
    end
  end

  describe "get_value/2" do
    test "gets value with string/atom key fallback" do
      assert EntityUtils.get_value(%{test: 123}, "test") == 123
      assert EntityUtils.get_value(%{"test" => 123}, :test) == 123
      assert EntityUtils.get_value(%{test: 123}, :test) == 123
      assert EntityUtils.get_value(%{"test" => 123}, "test") == 123
    end

    test "returns nil for missing keys" do
      assert EntityUtils.get_value(%{}, "test") == nil
      assert EntityUtils.get_value(%{other: 123}, :test) == nil
    end
  end

  describe "normalize_id/1" do
    test "normalizes various ID formats" do
      assert EntityUtils.normalize_id(123) == 123
      assert EntityUtils.normalize_id("123") == 123
      assert EntityUtils.normalize_id(123.0) == 123
      assert EntityUtils.normalize_id(123.7) == 123
    end

    test "returns nil for invalid formats" do
      assert EntityUtils.normalize_id("invalid") == nil
      assert EntityUtils.normalize_id("123abc") == nil
      assert EntityUtils.normalize_id(nil) == nil
      assert EntityUtils.normalize_id(%{}) == nil
    end
  end

  describe "parse_integer/2" do
    test "parses integers with default" do
      assert EntityUtils.parse_integer(123) == 123
      assert EntityUtils.parse_integer("123") == 123
      assert EntityUtils.parse_integer("123abc") == 123
      assert EntityUtils.parse_integer("invalid", 0) == 0
      assert EntityUtils.parse_integer(nil, 999) == 999
    end
  end

  describe "parse_float/2" do
    test "parses floats with default" do
      assert EntityUtils.parse_float(123.45) == 123.45
      assert EntityUtils.parse_float(123) == 123.0
      assert EntityUtils.parse_float("123.45") == 123.45
      assert EntityUtils.parse_float("invalid", 0.0) == 0.0
      assert EntityUtils.parse_float(nil, 99.9) == 99.9
    end
  end
end
