defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationFormatterTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}

  describe "format_notification/1 with killmail" do
    test "formats basic killmail notification" do
      killmail = %Killmail{
        killmail_id: "123456",
        victim_character_name: "Test Victim",
        victim_ship_name: "Rifter",
        system_name: "Jita",
        system_id: 30_000_142,
        value: 1_000_000,
        attackers: [],
        kill_time: "2024-01-01T12:00:00Z"
      }

      result = NotificationFormatter.format_notification(killmail)

      assert result.type == :kill_notification
      assert result.title == "Test Victim's Rifter destroyed"
      assert is_binary(result.description)
      assert is_list(result.fields)
      assert is_map(result.footer)
    end

    test "handles killmail without character name" do
      killmail = %Killmail{
        killmail_id: "123456",
        victim_character_name: nil,
        victim_ship_name: "Capsule",
        system_name: "Jita",
        system_id: 30_000_142,
        value: 0,
        attackers: []
      }

      result = NotificationFormatter.format_notification(killmail)

      assert result.title == "Capsule destroyed"
    end
  end

  describe "format_notification/1 with character" do
    test "formats basic character notification" do
      character = %Character{
        character_id: 123_456,
        name: "Test Character",
        corporation_ticker: "TEST",
        alliance_ticker: "ALLY"
      }

      result = NotificationFormatter.format_notification(character)

      assert result.type == :character_notification
      assert result.title == "New Character Tracked: Test Character"
      assert String.contains?(result.description, "[TEST]")
      assert String.contains?(result.description, "<ALLY>")
      assert is_list(result.fields)
    end

    test "handles character without corporation/alliance" do
      character = %Character{
        character_id: 123_456,
        name: "Solo Character",
        corporation_ticker: nil,
        alliance_ticker: nil
      }

      result = NotificationFormatter.format_notification(character)

      assert result.description == "A new character has been added to tracking."
    end
  end

  describe "format_notification/1 with system" do
    test "formats basic system notification" do
      system = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        region_name: "Anoikis",
        type_description: "C1"
      }

      result = NotificationFormatter.format_notification(system)

      assert result.type == :system_notification
      assert result.title == "New System Tracked: J123456"
      assert is_binary(result.description)
      assert is_list(result.fields)
    end

    test "handles wormhole system with class" do
      system = %System{
        solar_system_id: 31_000_001,
        name: "J123456",
        class_title: "Class 1",
        system_type: :wormhole,
        is_shattered: false,
        statics: ["H121", "O883"]
      }

      result = NotificationFormatter.format_notification(system)

      assert String.contains?(result.description, "Class 1")
    end
  end

  describe "format_plain_text/1" do
    test "formats kill notification as plain text" do
      notification = %{
        type: :kill_notification,
        title: "Test Kill",
        description: "A valuable kill",
        url: "https://zkillboard.com/kill/123/",
        fields: [
          %{name: "System", value: "Jita"},
          %{name: "Value", value: "1.5M ISK"}
        ]
      }

      result = NotificationFormatter.format_plain_text(notification)

      assert String.contains?(result, "💀 Test Kill")
      assert String.contains?(result, "A valuable kill")
      assert String.contains?(result, "System: Jita")
      assert String.contains?(result, "Value: 1.5M ISK")
    end

    test "formats character notification as plain text" do
      notification = %{
        type: :character_notification,
        title: "New Character",
        description: "Character added",
        url: "https://evewho.com/character/123"
      }

      result = NotificationFormatter.format_plain_text(notification)

      assert String.contains?(result, "👤 New Character")
      assert String.contains?(result, "Character added")
    end

    test "formats system notification as plain text" do
      notification = %{
        type: :system_notification,
        title: "New System",
        description: "System added"
      }

      result = NotificationFormatter.format_plain_text(notification)

      assert String.contains?(result, "🌌 New System")
      assert String.contains?(result, "System added")
    end

    test "handles unknown notification type" do
      result = NotificationFormatter.format_plain_text(%{type: :unknown})
      assert result == "Notification"
    end
  end
end
