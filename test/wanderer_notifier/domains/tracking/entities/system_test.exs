defmodule WandererNotifier.Domains.Tracking.Entities.SystemTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Infrastructure.Cache

  setup do
    # Clear the cache before each test
    Cache.delete(Cache.Keys.map_systems())
    :ok
  end

  describe "new/1" do
    test "creates system with required fields" do
      attrs = %{
        "solar_system_id" => 30_000_142,
        "name" => "Jita"
      }

      system = System.new(attrs)

      assert system.solar_system_id == 30_000_142
      assert system.name == "Jita"
    end

    test "creates system with all optional fields" do
      attrs = %{
        "solar_system_id" => 31_001_234,
        "name" => "J123456",
        "id" => "J123456",
        "region_name" => "A-R00001",
        "statics" => ["C247", "P060"],
        "system_class" => "4",
        "class_title" => "C4",
        "type_description" => "C4 Wormhole",
        "is_shattered" => true,
        "effect_name" => "Pulsar",
        "security_status" => -0.5,
        "system_type" => "wormhole"
      }

      system = System.new(attrs)

      assert system.solar_system_id == 31_001_234
      assert system.name == "J123456"
      assert system.id == "J123456"
      assert system.region_name == "A-R00001"
      assert system.statics == ["C247", "P060"]
      assert system.system_class == "4"
      assert system.class_title == "C4"
      assert system.type_description == "C4 Wormhole"
      assert system.is_shattered == true
      assert system.effect_name == "Pulsar"
      assert system.security_status == -0.5
      assert system.system_type == "wormhole"
    end

    test "handles atom keys in input" do
      attrs = %{
        solar_system_id: 30_000_142,
        name: "Jita",
        region_name: "The Forge"
      }

      system = System.new(attrs)

      assert system.solar_system_id == 30_000_142
      assert system.name == "Jita"
      assert system.region_name == "The Forge"
    end

    test "ignores unknown fields" do
      attrs = %{
        "solar_system_id" => 30_000_142,
        "name" => "Jita",
        "unknown_field" => "ignored"
      }

      system = System.new(attrs)

      assert system.solar_system_id == 30_000_142
      assert system.name == "Jita"
      refute Map.has_key?(system, :unknown_field)
    end
  end

  describe "wormhole?/1" do
    test "returns true for wormhole systems with atom type" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "system_type" => :wormhole
        })

      assert System.wormhole?(system)
    end

    test "returns true for wormhole systems with string type" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "system_type" => "wormhole"
        })

      assert System.wormhole?(system)
    end

    test "returns true for wormhole systems with capitalized type" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "system_type" => "Wormhole"
        })

      assert System.wormhole?(system)
    end

    test "returns false for non-wormhole systems" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita",
          "system_type" => "k-space"
        })

      refute System.wormhole?(system)
    end

    test "returns false when system_type is nil" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita"
        })

      refute System.wormhole?(system)
    end
  end

  describe "kspace?/1" do
    test "returns true for k-space systems" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita",
          "system_class" => "K"
        })

      assert System.kspace?(system)
    end

    test "returns true for high-sec systems" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita",
          "system_class" => "HS"
        })

      assert System.kspace?(system)
    end

    test "returns true for low-sec systems" do
      system =
        System.new(%{
          "solar_system_id" => 30_002_659,
          "name" => "Rancer",
          "system_class" => "LS"
        })

      assert System.kspace?(system)
    end

    test "returns true for null-sec systems" do
      system =
        System.new(%{
          "solar_system_id" => 30_004_759,
          "name" => "1DH-SX",
          "system_class" => "NS"
        })

      assert System.kspace?(system)
    end

    test "returns false for wormhole systems" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "system_class" => "4"
        })

      refute System.kspace?(system)
    end

    test "returns false when system_class is nil" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita"
        })

      refute System.kspace?(system)
    end

    test "works with plain maps" do
      system_map = %{system_class: "HS"}
      assert System.kspace?(system_map)

      wormhole_map = %{system_class: "4"}
      refute System.kspace?(wormhole_map)
    end
  end

  describe "format_display_name/1" do
    test "formats name with class and effect" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "class_title" => "C4",
          "effect_name" => "Pulsar"
        })

      assert System.format_display_name(system) == "J123456 C4 Pulsar"
    end

    test "formats name with class only" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "class_title" => "C4"
        })

      assert System.format_display_name(system) == "J123456 C4"
    end

    test "formats name only when class and effect are nil" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita"
        })

      assert System.format_display_name(system) == "Jita"
    end

    test "skips nil values in formatting" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "class_title" => nil,
          "effect_name" => "Pulsar"
        })

      assert System.format_display_name(system) == "J123456 Pulsar"
    end
  end

  describe "update_with_static_info/2" do
    test "updates system with static information" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456"
        })

      static_info = %{
        "class_title" => "C4",
        "effect_name" => "Pulsar",
        "is_shattered" => true,
        "statics" => ["C247", "P060"],
        "system_type" => "wormhole"
      }

      updated_system = System.update_with_static_info(system, static_info)

      assert updated_system.class_title == "C4"
      assert updated_system.effect_name == "Pulsar"
      assert updated_system.is_shattered == true
      assert updated_system.statics == ["C247", "P060"]
      assert updated_system.system_type == "wormhole"
      # Original fields should be preserved
      assert updated_system.solar_system_id == 31_001_234
      assert updated_system.name == "J123456"
    end

    test "normalizes system_class from integer to string" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456"
        })

      static_info = %{
        system_class: 4
      }

      updated_system = System.update_with_static_info(system, static_info)

      assert updated_system.system_class == "4"
    end

    test "handles string keys in static info" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456"
        })

      static_info = %{
        "class_title" => "C4",
        "effect_name" => "Pulsar"
      }

      updated_system = System.update_with_static_info(system, static_info)

      assert updated_system.class_title == "C4"
      assert updated_system.effect_name == "Pulsar"
    end

    test "filters out invalid fields from static info" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456"
        })

      static_info = %{
        "class_title" => "C4",
        "invalid_field" => "should_be_ignored"
      }

      updated_system = System.update_with_static_info(system, static_info)

      assert updated_system.class_title == "C4"
      refute Map.has_key?(updated_system, :invalid_field)
    end
  end

  describe "validate_types/1" do
    test "validates system with correct types" do
      system =
        System.new(%{
          "solar_system_id" => 30_000_142,
          "name" => "Jita",
          "security_status" => 0.946,
          "region_id" => 10_000_002,
          "is_shattered" => false,
          "statics" => ["C247"]
        })

      assert :ok = System.validate_types(system)
    end

    test "raises error for invalid name type" do
      # Create system with invalid name type by bypassing new/1
      system = %System{solar_system_id: 30_000_142, name: 123}

      assert_raise ArgumentError, ~r/System.name must be a string/, fn ->
        System.validate_types(system)
      end
    end

    test "validates optional fields correctly" do
      system =
        System.new(%{
          # Can be string
          "solar_system_id" => "30000142",
          "name" => "Jita",
          "region_name" => "The Forge",
          "security_status" => 0.946,
          # Can be nil
          "is_shattered" => nil
        })

      assert :ok = System.validate_types(system)
    end
  end

  describe "is_tracked?/1" do
    test "returns true when system is in cached list" do
      systems = [
        %{"solar_system_id" => "30000142", "name" => "Jita"},
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      assert {:ok, true} = System.is_tracked?("30000142")
    end

    test "returns false when system is not in cached list" do
      systems = [
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      assert {:ok, false} = System.is_tracked?("30000142")
    end

    test "returns false when cache is empty" do
      # Cache is already cleared in setup
      assert {:ok, false} = System.is_tracked?("30000142")
    end

    test "handles integer system_id" do
      systems = [
        %{"solar_system_id" => "30000142", "name" => "Jita"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      assert {:ok, true} = System.is_tracked?(30_000_142)
    end

    test "returns error for invalid system_id" do
      assert {:error, :invalid_system_id} = System.is_tracked?(nil)
      assert {:error, :invalid_system_id} = System.is_tracked?(%{})
    end

    test "handles mixed key formats in cache" do
      systems = [
        %{:solar_system_id => "30000142", "name" => "Jita"},
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      assert {:ok, true} = System.is_tracked?("30000142")
      assert {:ok, true} = System.is_tracked?("30002659")
    end
  end

  describe "get_system/1" do
    test "returns system when found in cache" do
      systems = [
        %{"id" => "30000142", "name" => "Jita"},
        %{"id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      system = System.get_system("30000142")
      assert system["name"] == "Jita"
    end

    test "returns nil when system not found" do
      systems = [
        %{"id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      assert System.get_system("30000142") == nil
    end

    test "returns nil when cache is empty" do
      # Cache already cleared in setup
      assert System.get_system("30000142") == nil
    end
  end

  describe "get_system_by_name/1" do
    test "returns system when found by name" do
      systems = [
        %{"id" => "30000142", "name" => "Jita"},
        %{"id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      system = System.get_system_by_name("Jita")
      assert system["id"] == "30000142"
    end

    test "returns nil when system name not found" do
      systems = [
        %{"id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put(Cache.Keys.map_systems(), systems)

      assert System.get_system_by_name("Jita") == nil
    end

    test "returns nil when cache is empty" do
      # Cache already cleared in setup
      assert System.get_system_by_name("Jita") == nil
    end
  end
end
