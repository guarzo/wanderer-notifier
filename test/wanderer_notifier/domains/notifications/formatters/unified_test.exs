defmodule WandererNotifier.Domains.Notifications.Formatters.UnifiedTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Notifications.Formatters.Unified
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}
  alias WandererNotifier.Test.Support.TestHelpers

  describe "format_notification/1" do
    test "formats killmail notifications" do
      killmail = TestHelpers.create_test_killmail()

      notification = Unified.format_notification(killmail)

      assert notification.type == :kill_notification
      assert notification.title =~ "Test Victim"
      assert notification.description =~ "150.0M ISK"
      # kill color
      assert notification.color == 0xD9534F
      assert notification.url =~ "zkillboard.com"
      assert is_list(notification.fields)
      assert length(notification.fields) > 0
    end

    test "formats character notifications" do
      character = %Character{
        character_id: "123456",
        name: "Test Character",
        corporation_ticker: "TEST",
        alliance_ticker: "ALLY"
      }

      notification = Unified.format_notification(character)

      assert notification.type == :character_notification
      assert notification.title == "New Character Tracked: Test Character"
      assert notification.description =~ "[TEST]"
      assert notification.description =~ "<ALLY>"
      # character color
      assert notification.color == 0x3498DB
      assert notification.url =~ "evewho.com"
    end

    test "formats system notifications" do
      system = %System{
        solar_system_id: 30_000_142,
        name: "Jita",
        region_name: "The Forge",
        system_type: :highsec,
        type_description: "High Sec"
      }

      notification = Unified.format_notification(system)

      assert notification.type == :system_notification
      assert notification.title == "New System Tracked: Jita"
      assert notification.description =~ "High Sec"
      # highsec color
      assert notification.color == 0x5CB85C
      assert is_list(notification.fields)
    end

    test "formats wormhole system notifications with statics" do
      system = %System{
        solar_system_id: 31_001_234,
        name: "J123456",
        system_type: :wormhole,
        class_title: "C4",
        is_shattered: true,
        statics: ["C247", "P060"],
        effect_name: "Pulsar"
      }

      notification = Unified.format_notification(system)

      assert notification.type == :system_notification
      assert notification.title == "New System Tracked: J123456"
      assert notification.description =~ "C4"
      # wormhole color
      assert notification.color == 0x428BCA

      # Check for wormhole-specific fields
      fields = notification.fields
      assert Enum.any?(fields, fn f -> f.name == "Shattered" and f.value == "Yes" end)
      assert Enum.any?(fields, fn f -> f.name == "Statics" and f.value =~ "C247" end)
      assert Enum.any?(fields, fn f -> f.name == "Effect" and f.value == "Pulsar" end)
    end
  end

  describe "format_plain_text/1" do
    test "formats killmail as plain text" do
      killmail = TestHelpers.create_test_killmail()
      notification = Unified.format_notification(killmail)

      plain_text = Unified.format_plain_text(notification)

      assert plain_text =~ "💀"
      assert plain_text =~ "Test Victim"
      assert plain_text =~ "zkillboard.com"
    end

    test "formats character as plain text" do
      character = %Character{
        character_id: "123456",
        name: "Test Character",
        corporation_ticker: "TEST"
      }

      notification = Unified.format_notification(character)

      plain_text = Unified.format_plain_text(notification)

      assert plain_text =~ "👤"
      assert plain_text =~ "Test Character"
    end

    test "formats system as plain text" do
      system = %System{
        solar_system_id: 30_000_142,
        name: "Jita",
        system_type: :highsec
      }

      notification = Unified.format_notification(system)

      plain_text = Unified.format_plain_text(notification)

      assert plain_text =~ "🌌"
      assert plain_text =~ "Jita"
    end
  end

  describe "killmail field building" do
    test "includes victim field when character name is present" do
      killmail = TestHelpers.create_test_killmail(victim_id: 987_654)

      notification = Unified.format_notification(killmail)

      victim_field = Enum.find(notification.fields, fn f -> f.name == "Victim" end)
      assert victim_field != nil
      assert victim_field.value =~ "Test Victim"
      assert victim_field.value =~ "evewho.com"
    end

    test "includes final blow field when attackers are present" do
      killmail = TestHelpers.create_test_killmail()

      notification = Unified.format_notification(killmail)

      final_blow_field = Enum.find(notification.fields, fn f -> f.name == "Final Blow" end)
      assert final_blow_field != nil
      assert final_blow_field.value =~ "Test Attacker"
    end

    test "includes value field when value is present" do
      killmail = TestHelpers.create_test_killmail()

      notification = Unified.format_notification(killmail)

      value_field = Enum.find(notification.fields, fn f -> f.name == "Value" end)
      assert value_field != nil
      assert value_field.value == "150.0M ISK"
    end
  end
end
