defmodule WandererNotifier.Infrastructure.Cache.KeysTest do
  use ExUnit.Case
  alias WandererNotifier.Infrastructure.Cache.Keys

  describe "key generation macros" do
    test "system/1 generates correct key" do
      assert Keys.system("12345") == "map:system:12345"
      assert Keys.system(12_345) == "map:system:12345"
    end

    test "character/1 generates correct key" do
      assert Keys.character("12345") == "esi:character:12345"
      assert Keys.character(12_345) == "esi:character:12345"
    end

    test "tracked_system/1 generates correct key" do
      assert Keys.tracked_system("12345") == "tracked:system:12345"
      assert Keys.tracked_system(12_345) == "tracked:system:12345"
    end

    test "esi_killmail/1 generates correct key" do
      assert Keys.esi_killmail("12345") == "esi:killmail:12345"
      assert Keys.esi_killmail(12_345) == "esi:killmail:12345"
    end

    test "killmail/2 generates correct key" do
      assert Keys.killmail("12345", "abc123") == "esi:killmail:12345:abc123"
      assert Keys.killmail(12_345, "abc123") == "esi:killmail:12345:abc123"
    end

    test "alliance/1 generates correct key" do
      assert Keys.alliance("12345") == "esi:alliance:12345"
      assert Keys.alliance(12_345) == "esi:alliance:12345"
    end

    test "corporation/1 generates correct key" do
      assert Keys.corporation("12345") == "esi:corporation:12345"
      assert Keys.corporation(12_345) == "esi:corporation:12345"
    end

    test "ship_type/1 generates correct key" do
      assert Keys.ship_type("12345") == "esi:ship_type:12345"
      assert Keys.ship_type(12_345) == "esi:ship_type:12345"
    end

    test "functions with optional extra parameter" do
      assert Keys.system("12345", "extra") == "map:system:12345:extra"
      assert Keys.character("12345", "detail") == "esi:character:12345:detail"
    end

    test "key generation macros nil values are filtered out" do
      assert Keys.alliance(nil) == "esi:alliance:"
      assert Keys.corporation(nil) == "esi:corporation:"
      assert Keys.character(nil) == "esi:character:"
    end
  end

  describe "non-macro functions" do
    test "killmail_exists/3 generates correct key" do
      assert Keys.killmail_exists(12_345, 67_890, "victim") ==
               "exists:killmail:12345:67890:victim"
    end

    test "character_recent_kills/1 generates correct key" do
      assert Keys.character_recent_kills(12_345) == "character:12345:recent_kills"
    end

    test "character_list/0 generates correct key" do
      assert Keys.character_list() == "map:characters"
    end

    test "kill_comparison/2 generates correct key" do
      assert Keys.kill_comparison("daily", "date=2023-05-01") ==
               "kill_comparison:daily:date=2023-05-01"
    end

    test "tracked_systems/0 generates correct key" do
      assert Keys.tracked_systems() == "tracked:systems"
    end

    test "tracked_systems_list/0 generates correct key" do
      assert Keys.tracked_systems_list() == "tracked:systems"
    end

    test "config keys" do
      assert Keys.config("api") == "config:api"
      assert Keys.config("cache") == "config:cache"
      assert Keys.config("license") == "config:license"
      assert Keys.config("feature") == "config:feature"
      assert Keys.config("test") == "config:test"
      assert Keys.config("redisq") == "config:redisq"
    end
  end

  describe "key validation and extraction" do
    test "valid?/1 validates keys" do
      assert Keys.valid?("map:system:12345") == true
      assert Keys.valid?("invalid") == false
      assert Keys.valid?(nil) == false
    end

    test "extract_pattern/2 extracts parts based on patterns" do
      assert Keys.extract_pattern("map:system:12345", "map:system:*") == ["12345"]
      assert Keys.extract_pattern("map:character:98765", "map:*:*") == ["character", "98765"]
      assert Keys.extract_pattern("invalid", "map:*") == []
      assert Keys.extract_pattern("map:different:12345", "map:system:*") == []
    end

    test "map_key_info/1 returns key details" do
      result = Keys.map_key_info("map:system:12345")
      assert result.prefix == "map"
      assert result.entity_type == "system"
      assert result.id == "12345"
      assert result.parts == ["map", "system", "12345"]

      # Simple key
      simple_result = Keys.map_key_info("prefix:name")
      assert simple_result.prefix == "prefix"
      assert simple_result.name == "name"

      # Invalid key
      assert Keys.map_key_info("invalid") == {:error, :invalid_key}
      assert Keys.map_key_info(nil) == {:error, :invalid_key}
    end
  end
end
