defmodule WandererNotifier.Domains.Notifications.Formatters.RallyFormatterTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Notifications.Formatters.RallyFormatter

  describe "format_embed/1" do
    test "formats rally point notification correctly" do
      rally_point = %{
        id: "rally-123",
        system_id: 30_000_142,
        system_name: "Jita",
        character_id: 12_345,
        character_name: "Test Pilot",
        corporation_name: "Test Corp",
        alliance_name: "Test Alliance"
      }

      result = RallyFormatter.format_embed(rally_point)

      assert result.title == "⚔️ Rally Point Created"
      assert result.description =~ "Test Pilot"
      assert result.description =~ "Jita"
      assert result.color == 0xFF6B00
      assert result.footer.text == "Rally ID: rally-123"

      # Check fields
      fields = result.fields
      assert length(fields) == 4
      assert Enum.any?(fields, &(&1.name == "System" and &1.value == "Jita"))
      assert Enum.any?(fields, &(&1.name == "Created By" and &1.value == "Test Pilot"))
      assert Enum.any?(fields, &(&1.name == "Corporation" and &1.value == "Test Corp"))
      assert Enum.any?(fields, &(&1.name == "Alliance" and &1.value == "Test Alliance"))
    end

    test "handles rally point without corporation and alliance" do
      rally_point = %{
        id: "rally-456",
        system_id: 30_000_142,
        system_name: "Amarr",
        character_id: 67_890,
        character_name: "Solo Pilot"
      }

      result = RallyFormatter.format_embed(rally_point)

      fields = result.fields
      assert length(fields) == 2
      assert Enum.any?(fields, &(&1.name == "System" and &1.value == "Amarr"))
      assert Enum.any?(fields, &(&1.name == "Created By" and &1.value == "Solo Pilot"))
    end
  end

  describe "format_plain_text/1" do
    test "formats rally point as plain text" do
      rally_point = %{
        id: "rally-789",
        system_name: "Dodixie",
        character_name: "Fleet Commander"
      }

      result = RallyFormatter.format_plain_text(rally_point)

      assert result == "Rally point created in Dodixie by Fleet Commander"
    end
  end
end
