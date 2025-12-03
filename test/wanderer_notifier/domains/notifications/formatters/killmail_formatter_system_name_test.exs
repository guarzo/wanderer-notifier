defmodule WandererNotifier.Domains.Notifications.Formatters.KillmailFormatterSystemNameTest do
  @moduledoc """
  Tests for custom system name handling in killmail notifications.

  These tests ensure that tracked systems display their Wanderer custom names
  instead of generic EVE system names (J-sigs for wormholes).
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
      Cachex.clear(Cache.cache_name())
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
          "ship_type_id" => 11567,
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
          "ship_type_id" => 11567,
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
          "ship_type_id" => 11567,
          "final_blow" => true,
          "damage_done" => 1000
        }
      ],
      value: 100_000_000,
      kill_time: "2024-01-15T12:00:00Z"
    }
  end

  describe "custom system name in notifications" do
    test "uses custom_name when system is tracked and has custom name" do
      system_id = 31_000_001

      # Cache system with custom name (simulating API/SSE data)
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J123456",
        "custom_name" => "Home System",
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J123456", 12345)
      result = KillmailFormatter.format(killmail)

      # Verify custom name is used in title (system name is now in title)
      assert result.title =~ "Home System"
      refute result.title =~ "J123456"
    end

    test "uses temporary_name when custom_name is not set" do
      system_id = 31_000_002

      # Cache system with temporary name but no custom name
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J234567",
        "custom_name" => nil,
        "temporary_name" => "Temp Staging"
      })

      killmail = build_killmail(system_id, "J234567", 12346)
      result = KillmailFormatter.format(killmail)

      # Verify temporary name is used in title
      assert result.title =~ "Temp Staging"
      refute result.title =~ "J234567"
    end

    test "uses fallback system name when no custom or temporary name exists" do
      system_id = 31_000_003

      # Cache system without custom or temporary name
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J345678",
        "custom_name" => nil,
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J345678", 12347)
      result = KillmailFormatter.format(killmail)

      # Should use the killmail's system_name as fallback in title
      assert result.title =~ "J345678"
    end

    test "uses fallback when system is not in tracked cache" do
      # Don't cache anything for this system
      system_id = 31_000_004

      killmail = build_killmail(system_id, "J456789", 12348)
      result = KillmailFormatter.format(killmail)

      # Should use the killmail's system_name in title
      assert result.title =~ "J456789"
    end

    test "ignores empty string custom_name" do
      system_id = 31_000_005

      # Cache system with empty string custom name
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J567890",
        "custom_name" => "",
        "temporary_name" => nil
      })

      killmail = build_killmail(system_id, "J567890", 12349)
      result = KillmailFormatter.format(killmail)

      # Should use the killmail's system_name (not empty string) in title
      assert result.title =~ "J567890"
    end

    test "custom_name takes priority over temporary_name" do
      system_id = 31_000_006

      # Cache system with both names
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J678901",
        "custom_name" => "Primary Name",
        "temporary_name" => "Secondary Name"
      })

      killmail = build_killmail(system_id, "J678901", 12350)
      result = KillmailFormatter.format(killmail)

      # Should use custom_name, not temporary_name, in title
      assert result.title =~ "Primary Name"
      refute result.title =~ "Secondary Name"
    end
  end

  describe "character-tracked kills use EVE system name" do
    test "uses EVE system name when victim is tracked character" do
      system_id = 31_000_007
      tracked_victim_id = 95_000_001

      # Cache the system with custom name
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J789012",
        "custom_name" => "Should Not Appear",
        "temporary_name" => nil
      })

      # Cache the tracked character
      Cache.put_tracked_character(tracked_victim_id, %{
        "character" => %{"eve_id" => tracked_victim_id, "name" => "Tracked Pilot"}
      })

      killmail =
        build_killmail_with_victim(
          system_id,
          "J789012",
          12351,
          tracked_victim_id,
          "Tracked Pilot"
        )

      result = KillmailFormatter.format(killmail)

      # For character-tracked kills, should use EVE system name in title, not custom
      assert result.title =~ "J789012"
      refute result.title =~ "Should Not Appear"
    end

    test "uses EVE system name when attacker is tracked character" do
      system_id = 31_000_008
      tracked_attacker_id = 95_000_002

      # Cache the system with custom name
      Cache.put_tracked_system(to_string(system_id), %{
        "solar_system_id" => system_id,
        "solar_system_name" => "J890123",
        "custom_name" => "Should Not Appear Either",
        "temporary_name" => nil
      })

      # Cache the tracked character
      Cache.put_tracked_character(tracked_attacker_id, %{
        "character" => %{"eve_id" => tracked_attacker_id, "name" => "Tracked Hunter"}
      })

      killmail =
        build_killmail_with_attacker(
          system_id,
          "J890123",
          12352,
          tracked_attacker_id,
          "Tracked Hunter"
        )

      result = KillmailFormatter.format(killmail)

      # For character-tracked kills, should use EVE system name in title, not custom
      assert result.title =~ "J890123"
      refute result.title =~ "Should Not Appear Either"
    end
  end
end
