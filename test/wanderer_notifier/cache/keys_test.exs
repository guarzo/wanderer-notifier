defmodule WandererNotifier.Cache.KeysTest do
  use ExUnit.Case

  alias WandererNotifier.Cache.Keys

  describe "key generation" do
    test "system/1 generates correct system key" do
      assert Keys.system(30_004_759) == "map:system:30004759"
      assert Keys.system("30004759") == "map:system:30004759"
    end

    test "character/1 generates correct character key" do
      assert Keys.character(12_345) == "map:character:12345"
      assert Keys.character("12345") == "map:character:12345"
    end

    test "tracked_system/1 generates correct tracked system key" do
      assert Keys.tracked_system(30_004_759) == "tracked:system:30004759"
      assert Keys.tracked_system("30004759") == "tracked:system:30004759"
    end

    test "tracked_character/1 generates correct tracked character key" do
      assert Keys.tracked_character(12_345) == "tracked:character:12345"
      assert Keys.tracked_character("12345") == "tracked:character:12345"
    end

    test "esi_killmail/1 generates correct ESI killmail key" do
      assert Keys.esi_killmail(98_765) == "esi:killmail:98765"
      assert Keys.esi_killmail("98765") == "esi:killmail:98765"
    end

    test "recent_kills/0 generates correct recent kills key" do
      assert Keys.recent_kills() == "recent:kills"
    end

    test "killmail_exists/3 generates correct existence check key" do
      assert Keys.killmail_exists(123, 456, "attacker") == "exists:killmail:123:456:attacker"
      assert Keys.killmail_exists("123", "456", "victim") == "exists:killmail:123:456:victim"
    end

    test "character_recent_kills/1 generates correct character recent kills key" do
      assert Keys.character_recent_kills(12_345) == "character:12345:recent_kills"
      assert Keys.character_recent_kills("12345") == "character:12345:recent_kills"
    end

    test "zkill_recent_kills/0 generates correct zkill recent kills key" do
      assert Keys.zkill_recent_kills() == "zkill:recent_kills"
    end
  end

  describe "key validation" do
    test "valid?/1 returns true for valid keys" do
      assert Keys.valid?("map:system:12345")
      assert Keys.valid?("recent:kills")
      assert Keys.valid?("exists:killmail:123:456:attacker")
    end

    test "valid?/1 returns false for invalid keys" do
      refute Keys.valid?("invalid-key")
      refute Keys.valid?("map")
      refute Keys.valid?("")
    end
  end

  describe "pattern extraction" do
    test "extract_pattern/1 extracts correct pattern from keys" do
      assert Keys.extract_pattern("map:system:12345") == "map:system"
      assert Keys.extract_pattern("recent:kills") == "recent:kills"
      assert Keys.extract_pattern("map:character:98765") == "map:character"
    end
  end

  describe "key type detection" do
    test "is_array_key?/1 identifies array keys correctly" do
      assert Keys.is_array_key?("array:data")
      assert Keys.is_array_key?("list:items")
      assert Keys.is_array_key?("recent:kills")
      refute Keys.is_array_key?("map:system:12345")
    end

    test "is_map_key?/1 identifies map keys correctly" do
      assert Keys.is_map_key?("map:system:12345")
      assert Keys.is_map_key?("data:items")
      assert Keys.is_map_key?("config:settings")
      refute Keys.is_map_key?("array:data")
    end

    test "is_critical_key?/1 identifies critical keys correctly" do
      assert Keys.is_critical_key?("critical:app_state")
      assert Keys.is_critical_key?("license_status")
      assert Keys.is_critical_key?("core_config")
      refute Keys.is_critical_key?("map:system:12345")
    end

    test "is_state_key?/1 identifies state keys correctly" do
      assert Keys.is_state_key?("state:app_data")
      assert Keys.is_state_key?("app:settings")
      assert Keys.is_state_key?("config:app")
      refute Keys.is_state_key?("map:system:12345")
    end

    test "is_static_info_key?/1 identifies static info keys correctly" do
      assert Keys.is_static_info_key?("map:system:static_info")
      assert Keys.is_static_info_key?("data:static_info")
      refute Keys.is_static_info_key?("map:system:12345")
    end
  end
end
