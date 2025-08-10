defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationFormatterRallyTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter

  describe "format_notification/1 with rally points" do
    test "formats rally point notification correctly" do
      rally_point = %{
        id: "rally-123",
        system_id: 30_000_142,
        system_name: "Jita",
        character_id: 12_345,
        character_name: "Test Pilot",
        corporation_name: "Test Corp"
      }

      result = NotificationFormatter.format_notification(rally_point)

      assert result.title == "⚔️ Rally Point Created"
      assert result.description =~ "Test Pilot"
      assert result.description =~ "Jita"
    end

    test "formats rally point plain text correctly" do
      rally_point = %{
        id: "rally-456",
        system_name: "Amarr",
        character_name: "Fleet Commander"
      }

      result = NotificationFormatter.format_plain_text(rally_point)

      assert result == "Rally point created in Amarr by Fleet Commander"
    end

    test "does not return error for rally points" do
      rally_point = %{
        id: "rally-789",
        system_name: "Dodixie",
        character_name: "Solo Pilot"
      }

      result = NotificationFormatter.format_notification(rally_point)

      refute result == {:error, :unknown_notification_type}
      assert is_map(result)
      assert result.title == "⚔️ Rally Point Created"
    end
  end
end
