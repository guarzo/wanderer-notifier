defmodule WandererNotifier.Domains.Notifications.Formatters.KillmailFormatterSystemNameTest do
  @moduledoc """
  Tests for custom system name handling in killmail notifications.

  These tests ensure that tracked systems display their Wanderer custom names
  instead of generic EVE system names (J-sigs for wormholes).

  The behavior is controlled by the `use_custom_system_name` option:
  - When `true` (system kill channel): Uses Wanderer custom/temporary name
  - When `false` (character kill channel or default): Uses EVE system name
  """

  use ExUnit.Case, async: false

  import Mox

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Notifications.Formatters.KillmailFormatter
  alias WandererNotifier.Infrastructure.Cache

  setup :verify_on_exit!

  setup do
    # Setup ESI mocks for ship type lookups
    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_universe_type, fn _id,
                                                                                         _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_corporation_info, fn _id,
                                                                                            _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)

    # Clear relevant cache entries before each test
    on_exit(fn ->
      # Clean up any cached data after each test
      Cache.clear()
    end)

    :ok
  end

  defp build_killmail(system_id, system_name, killmail_id) do
    %Killmail{
      killmail_id: killmail_id,
      system_id: system_id,
      system_name: system_name,
      victim_character_id: 99_999_999,
      victim_character_name: "Some Pilot",
      victim_corporation_id: 98_000_001,
      victim_ship_type_id: 582,
      attackers: [
        %{
          "character_id" => 88_888_888,
          "corporation_id" => 98_000_002,
          "ship_type_id" => 11_567,
          "final_blow" => true,
          "damage_done" => 1000
        }
      ],
      value: 100_000_000,
      kill_time: "2024-01-15T12:00:00Z"
    }
  end

  defp build_killmail_with_victim(system_id, system_name, killmail_id, victim_id, victim_name) do
    %Killmail{
      killmail_id: killmail_id,
      system_id: system_id,
      system_name: system_name,
      victim_character_id: victim_id,
      victim_character_name: victim_name,
      victim_corporation_id: 98_000_001,
      victim_ship_type_id: 582,
      attackers: [
        %{
          "character_id" => 88_888_888,
          "corporation_id" => 98_000_002,
          "ship_type_id" => 11_567,
          "final_blow" => true,
          "damage_done" => 1000
        }
      ],
      value: 100_000_000,
      kill_time: "2024-01-15T12:00:00Z"
    }
  end

  defp build_killmail_with_attacker(
         system_id,
         system_name,
         killmail_id,
         attacker_id,
         attacker_name
       ) do
    %Killmail{
      killmail_id: killmail_id,
      system_id: system_id,
      system_name: system_name,
      victim_character_id: 99_999_999,
      victim_character_name: "Random Victim",
      victim_corporation_id: 98_000_001,
      victim_ship_type_id: 582,
      attackers: [
        %{
          "character_id" => attacker_id,
          "character_name" => attacker_name,
          "corporation_id" => 98_000_002,
          "ship_type_id" => 11_567,
          "final_blow" => true,
          "damage_done" => 1000
        }
      ],
      value: 100_000_000,
      kill_time: "2024-01-15T12:00:00Z"
    }
  end

  describe "system kill channel (use_custom_system_name: true)" do
    test "uses custom_name when system is tracked and has custom name" do
      system_id = 31_000_001

      # Cache system with custom name (simulating API/SSE data)
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J123456",
        "custom_name" => "Home System",
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J123456", 12_345)
      # Simulate system kill channel by passing use_custom_system_name: true
      result = KillmailFormatter.format(killmail, use_custom_system_name: true)

      # Verify custom name is used in title
      assert result.title =~ "Home System"
      refute result.title =~ "J123456"
    end

    test "uses temporary_name when custom_name is not set" do
      system_id = 31_000_002

      # Cache system with temporary name but no custom name
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J234567",
        "custom_name" => nil,
        "temporary_name" => "Temp Staging"
      })

      killmail = build_killmail(system_id, "J234567", 12_346)
      result = KillmailFormatter.format(killmail, use_custom_system_name: true)

      # Verify temporary name is used in title
      assert result.title =~ "Temp Staging"
      refute result.title =~ "J234567"
    end

    test "uses fallback system name when no custom or temporary name exists" do
      system_id = 31_000_003

      # Cache system without custom or temporary name
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J345678",
        "custom_name" => nil,
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J345678", 12_347)
      result = KillmailFormatter.format(killmail, use_custom_system_name: true)

      # Should use the killmail's system_name as fallback in title
      assert result.title =~ "J345678"
    end

    test "uses fallback when system is not in tracked cache" do
      # Don't cache anything for this system
      system_id = 31_000_004

      killmail = build_killmail(system_id, "J456789", 12_348)
      result = KillmailFormatter.format(killmail, use_custom_system_name: true)

      # Should use the killmail's system_name in title
      assert result.title =~ "J456789"
    end

    test "ignores empty string custom_name" do
      system_id = 31_000_005

      # Cache system with empty string custom name
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J567890",
        "custom_name" => "",
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J567890", 12_349)
      result = KillmailFormatter.format(killmail, use_custom_system_name: true)

      # Should use the killmail's system_name (not empty string) in title
      assert result.title =~ "J567890"
    end

    test "custom_name takes priority over temporary_name" do
      system_id = 31_000_006

      # Cache system with both names
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J678901",
        "custom_name" => "Primary Name",
        "temporary_name" => "Secondary Name"
      })

      killmail = build_killmail(system_id, "J678901", 12_350)
      result = KillmailFormatter.format(killmail, use_custom_system_name: true)

      # Should use custom_name, not temporary_name, in title
      assert result.title =~ "Primary Name"
      refute result.title =~ "Secondary Name"
    end
  end

  describe "character kill channel (use_custom_system_name: false or default)" do
    test "uses EVE system name even when custom_name exists" do
      system_id = 31_000_007

      # Cache system with custom name
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J789012",
        "custom_name" => "Should Not Appear",
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J789012", 12_351)
      # Default behavior (no option) should use EVE name
      result = KillmailFormatter.format(killmail)

      # Should use EVE system name, not custom
      assert result.title =~ "J789012"
      refute result.title =~ "Should Not Appear"
    end

    test "uses EVE system name with explicit use_custom_system_name: false" do
      system_id = 31_000_008

      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J890123",
        "custom_name" => "Also Should Not Appear",
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J890123", 12_352)
      result = KillmailFormatter.format(killmail, use_custom_system_name: false)

      # Should use EVE system name, not custom
      assert result.title =~ "J890123"
      refute result.title =~ "Also Should Not Appear"
    end

    test "uses EVE system name when victim is tracked character" do
      system_id = 31_000_009
      tracked_victim_id = 95_000_001

      # Cache the system with custom name
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J901234",
        "custom_name" => "Character Kill Custom Name",
        "temporary_name" => nil
      })

      # Cache the tracked character
      Cache.put_tracked_character(tracked_victim_id, %{
        "character" => %{"eve_id" => tracked_victim_id, "name" => "Tracked Pilot"}
      })

      killmail =
        build_killmail_with_victim(
          system_id,
          "J901234",
          12_353,
          tracked_victim_id,
          "Tracked Pilot"
        )

      # Default for character-tracked kills is EVE name
      result = KillmailFormatter.format(killmail)

      # Should use EVE system name in title
      assert result.title =~ "J901234"
      refute result.title =~ "Character Kill Custom Name"
    end

    test "uses EVE system name when attacker is tracked character" do
      system_id = 31_000_010
      tracked_attacker_id = 95_000_002

      # Cache the system with custom name
      system_id
      |> to_string()
      |> Cache.put_tracked_system(%{
        "solar_system_id" => system_id,
        "solar_system_name" => "J012345",
        "custom_name" => "Attacker Kill Custom Name",
        "temporary_name" => nil
      })

      # Cache the tracked character
      Cache.put_tracked_character(tracked_attacker_id, %{
        "character" => %{"eve_id" => tracked_attacker_id, "name" => "Tracked Hunter"}
      })

      killmail =
        build_killmail_with_attacker(
          system_id,
          "J012345",
          12_354,
          tracked_attacker_id,
          "Tracked Hunter"
        )

      # Default for character-tracked kills is EVE name
      result = KillmailFormatter.format(killmail)

      # Should use EVE system name in title
      assert result.title =~ "J012345"
      refute result.title =~ "Attacker Kill Custom Name"
    end
  end
end
