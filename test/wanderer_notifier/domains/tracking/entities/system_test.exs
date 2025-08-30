defmodule WandererNotifier.Domains.Tracking.Entities.SystemTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Infrastructure.Cache

  setup do
    # Clear the cache before each test
    Cache.delete("map:systems")
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
      assert system.region_name == "A-R00001"
      assert system.statics == ["C247", "P060"]
      assert system.class_title == "C4"
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
    test "returns true for wormhole systems with string type" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "system_type" => "wormhole"
        })

      assert System.wormhole?(system)
    end

    test "returns true for wormhole systems with atom type" do
      system =
        System.new(%{
          "solar_system_id" => 31_001_234,
          "name" => "J123456",
          "system_type" => :wormhole
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

  describe "is_tracked?/1" do
    test "returns true when system is in cached list" do
      systems = [
        %{"solar_system_id" => "30000142", "name" => "Jita"},
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put("map:systems", systems)

      assert {:ok, true} = System.is_tracked?("30000142")
    end

    test "returns false when system is not in cached list" do
      systems = [
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put("map:systems", systems)

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

      Cache.put("map:systems", systems)

      assert {:ok, true} = System.is_tracked?(30_000_142)
    end

    test "returns error for invalid system_id" do
      assert {:error, :invalid_system_id} = System.is_tracked?(nil)
      assert {:error, :invalid_system_id} = System.is_tracked?(%{})
    end
  end

  describe "get_system/1" do
    test "returns system when found in cache" do
      systems = [
        %{"solar_system_id" => "30000142", "name" => "Jita"},
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put("map:systems", systems)

      assert {:ok, system} = System.get_system("30000142")
      assert system.name == "Jita"
    end

    test "returns error when system not found" do
      systems = [
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put("map:systems", systems)

      assert {:error, :not_found} = System.get_system("30000142")
    end

    test "returns error when cache is empty" do
      # Cache already cleared in setup
      assert {:error, :not_found} = System.get_system("30000142")
    end
  end

  describe "get_system_by_name/1" do
    test "returns system when found by name" do
      systems = [
        %{"solar_system_id" => "30000142", "name" => "Jita"},
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put("map:systems", systems)

      assert {:ok, system} = System.get_system_by_name("Jita")
      assert system.solar_system_id == 30_000_142
    end

    test "returns error when system name not found" do
      systems = [
        %{"solar_system_id" => "30002659", "name" => "Rancer"}
      ]

      Cache.put("map:systems", systems)

      assert {:error, :not_found} = System.get_system_by_name("Jita")
    end

    test "returns error when cache is empty" do
      # Cache already cleared in setup
      assert {:error, :not_found} = System.get_system_by_name("Jita")
    end
  end
end
