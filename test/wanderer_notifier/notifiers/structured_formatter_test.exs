defmodule WandererNotifier.Notifiers.StructuredFormatterTest do
  use ExUnit.Case
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Data.Killmail

  describe "colors/0" do
    test "returns a map of color constants" do
      colors = StructuredFormatter.colors()
      assert is_map(colors)
      assert Map.has_key?(colors, :default)
      assert Map.has_key?(colors, :success)
      assert Map.has_key?(colors, :warning)
      assert Map.has_key?(colors, :error)
      assert Map.has_key?(colors, :info)
      assert Map.has_key?(colors, :wormhole)
      assert Map.has_key?(colors, :highsec)
      assert Map.has_key?(colors, :lowsec)
      assert Map.has_key?(colors, :nullsec)
    end
  end

  describe "convert_color/1" do
    test "converts atom color names to integer values" do
      assert StructuredFormatter.convert_color(:default) == StructuredFormatter.colors().default
      assert StructuredFormatter.convert_color(:success) == StructuredFormatter.colors().success
      assert StructuredFormatter.convert_color(:warning) == StructuredFormatter.colors().warning
      assert StructuredFormatter.convert_color(:error) == StructuredFormatter.colors().error
      assert StructuredFormatter.convert_color(:info) == StructuredFormatter.colors().info
    end

    test "returns integer color values unchanged" do
      assert StructuredFormatter.convert_color(0x3498DB) == 0x3498DB
      assert StructuredFormatter.convert_color(16_711_680) == 16_711_680
    end

    test "converts hex strings to integer values" do
      assert StructuredFormatter.convert_color("#FF0000") == 0xFF0000
      assert StructuredFormatter.convert_color("#00FF00") == 0x00FF00
      assert StructuredFormatter.convert_color("#0000FF") == 0x0000FF
    end

    test "returns default color for invalid inputs" do
      default_color = StructuredFormatter.colors().default
      assert StructuredFormatter.convert_color(nil) == default_color
      assert StructuredFormatter.convert_color("invalid") == default_color
      assert StructuredFormatter.convert_color([]) == default_color
    end
  end

  describe "format_kill_notification/1" do
    test "formats a killmail notification correctly" do
      # Create a test killmail
      zkb_data = %{
        "totalValue" => 150_000_000,
        "points" => 25
      }

      esi_data = %{
        "killmail_time" => "2023-04-15T12:30:45Z",
        "solar_system_id" => 30_002_082,
        "solar_system_name" => "Jita",
        "victim" => %{
          "character_id" => 12_345,
          "character_name" => "Test Victim",
          "ship_type_id" => 34_562,
          "ship_type_name" => "Nyx",
          "corporation_name" => "Test Corp",
          "alliance_name" => "Test Alliance"
        },
        "attackers" => [
          %{
            "character_id" => 67_890,
            "character_name" => "Test Attacker",
            "ship_type_id" => 11_987,
            "ship_type_name" => "Rifter",
            "corporation_name" => "Attacker Corp",
            "final_blow" => true
          }
        ]
      }

      killmail = Killmail.new("98765", zkb_data, esi_data)

      result = StructuredFormatter.format_kill_notification(killmail)

      # Check that the result has the expected structure
      assert is_map(result)
      assert result.type == :kill_notification
      assert result.title == "Kill Notification"
      assert result.description =~ "Test Victim"
      assert result.description =~ "Nyx"
      assert result.description =~ "Jita"
      assert result.color
      assert result.url =~ "zkillboard.com/kill/98765"
      assert result.timestamp == "2023-04-15T12:30:45Z"
      assert result.thumbnail.url =~ "34562"

      # Check author info
      assert result.author.name =~ "Test Victim"
      assert result.author.name =~ "Test Corp"
      assert result.author.icon_url =~ "12345"

      # Check fields
      assert length(result.fields) == 4
      assert Enum.any?(result.fields, fn field -> field.name == "Value" end)
      assert Enum.any?(result.fields, fn field -> field.name == "Attackers" end)
      assert Enum.any?(result.fields, fn field -> field.name == "Final Blow" end)
      assert Enum.any?(result.fields, fn field -> field.name == "Alliance" end)

      # Check final blow field details
      final_blow_field = Enum.find(result.fields, fn field -> field.name == "Final Blow" end)
      assert final_blow_field.value =~ "Test Attacker"
      assert final_blow_field.value =~ "Rifter"
    end

    test "handles killmail with missing or partial data" do
      # Create a minimal killmail
      zkb_data = %{"totalValue" => 1000}
      killmail = Killmail.new("12345", zkb_data)

      result = StructuredFormatter.format_kill_notification(killmail)

      # Check that the result still has the basic structure
      assert is_map(result)
      assert result.type == :kill_notification
      assert result.title == "Kill Notification"
      assert result.description =~ "Unknown Pilot"
      assert result.description =~ "Unknown Ship"
      assert result.description =~ "Unknown System"
      assert result.color
      assert result.url =~ "zkillboard.com/kill/12345"
    end
  end

  describe "format_character_notification/1" do
    test "formats a character notification correctly" do
      # Create a test character
      character = %Character{
        character_id: "12345",
        name: "Test Character",
        corporation_id: 67_890,
        corporation_ticker: "TSTC",
        alliance_id: 54_321,
        alliance_ticker: "TSTA",
        tracked: true
      }

      result = StructuredFormatter.format_character_notification(character)

      # Check that the result has the expected structure
      assert is_map(result)
      assert result.type == :character_notification
      assert result.title == "New Character Tracked"
      assert result.description =~ "new character"
      assert result.color
      assert result.thumbnail.url =~ "12345"
      assert result.fields

      # Check character field
      character_field = Enum.find(result.fields, fn field -> field.name == "Character" end)
      assert character_field
      assert character_field.value =~ "Test Character"
      assert character_field.value =~ "zkillboard.com/character/12345"

      # Check corporation field
      corporation_field = Enum.find(result.fields, fn field -> field.name == "Corporation" end)
      assert corporation_field
      assert corporation_field.value =~ "TSTC"
      assert corporation_field.value =~ "zkillboard.com/corporation/67890"
    end

    test "handles character without corporation data" do
      # Create a test character without corporation
      character = %Character{
        character_id: "12345",
        name: "Test Character",
        tracked: true
      }

      result = StructuredFormatter.format_character_notification(character)

      # Check that the result omits the corporation field
      assert is_map(result)
      assert result.type == :character_notification
      refute Enum.any?(result.fields, fn field -> field.name == "Corporation" end)
    end
  end

  describe "format_system_notification/1" do
    test "formats a wormhole system notification correctly" do
      # Create a test wormhole system
      system = %MapSystem{
        id: "map-123456",
        solar_system_id: 31_000_001,
        name: "J123456",
        original_name: "J123456",
        system_type: :wormhole,
        type_description: "Wormhole",
        class_title: "Class 5",
        effect_name: "Wolf-Rayet",
        is_shattered: false,
        locked: false,
        region_name: "Unknown",
        static_details: [
          %{
            "name" => "C140",
            "destination" => %{
              "short_name" => "C5"
            }
          },
          %{
            "name" => "N944",
            "destination" => %{
              "short_name" => "H"
            }
          }
        ],
        sun_type_id: 45_041
      }

      result = StructuredFormatter.format_system_notification(system)

      # Check that the result has the expected structure
      assert is_map(result)
      assert result.type == :system_notification
      assert result.title == "New Class 5 System Mapped"

      assert result.description ==
               "A Class 5 wormhole system has been discovered and added to the map."

      assert result.color
      assert result.thumbnail.url
      assert result.fields

      # Check system field
      system_field = Enum.find(result.fields, fn field -> field.name == "System" end)
      assert system_field
      assert system_field.value =~ "J123456"

      # Check statics field
      statics_field = Enum.find(result.fields, fn field -> field.name == "Statics" end)
      assert statics_field
      assert statics_field.value =~ "C140"
      assert statics_field.value =~ "N944"

      # Check effect field
      effect_field = Enum.find(result.fields, fn field -> field.name == "Effect" end)
      assert effect_field
      assert effect_field.value =~ "Wolf-Rayet"

      # Check region field
      region_field = Enum.find(result.fields, fn field -> field.name == "Region" end)
      assert region_field
      assert region_field.value =~ "Unknown"
    end

    test "formats a k-space system notification correctly" do
      # Create a test k-space system
      system = %MapSystem{
        solar_system_id: "30000142",
        name: "Jita",
        type_description: "High-sec",
        region_name: "The Forge",
        system_type: "k-space"
      }

      result = StructuredFormatter.format_system_notification(system)

      # Check that the result has the expected structure
      assert is_map(result)
      assert result.type == :system_notification
      assert result.title =~ "High-sec"
      assert result.description =~ "High-sec system"
      assert result.color
      assert result.thumbnail.url
      assert result.fields

      # Check system field
      system_field = Enum.find(result.fields, fn field -> field.name == "System" end)
      assert system_field
      assert system_field.value =~ "Jita"
      assert system_field.value =~ "zkillboard.com/system/30000142"

      # Check region field
      region_field = Enum.find(result.fields, fn field -> field.name == "Region" end)
      assert region_field
      assert region_field.value =~ "The Forge"
    end

    test "raises for system without required fields" do
      # Create structs missing required fields
      system_with_only_name = struct(MapSystem, %{name: "Test System"})
      system_with_only_id = struct(MapSystem, %{solar_system_id: 12_345})
      empty_system = MapSystem.new(%{})

      # Test with missing system ID
      assert_raise RuntimeError, ~r/solar_system_id is missing/, fn ->
        StructuredFormatter.format_system_notification(system_with_only_name)
      end

      # Test with missing name
      assert_raise RuntimeError, ~r/name is missing/, fn ->
        StructuredFormatter.format_system_notification(system_with_only_id)
      end

      # Test with both fields missing (from new)
      assert_raise RuntimeError, ~r/solar_system_id is missing|name is missing/, fn ->
        StructuredFormatter.format_system_notification(empty_system)
      end
    end
  end

  describe "to_discord_format/1" do
    test "converts a generic notification to Discord format" do
      # Create a generic notification with minimal fields
      notification = %{
        type: :test_notification,
        title: "Test Title",
        description: "Test Description",
        color: 0x3498DB,
        url: "https://example.com",
        timestamp: "2023-04-15T12:30:45Z",
        fields: [
          %{name: "Field 1", value: "Value 1", inline: true},
          %{name: "Field 2", value: "Value 2", inline: false}
        ]
      }

      result = StructuredFormatter.to_discord_format(notification)

      # Check that the result is in Discord format
      assert is_map(result)
      assert result["title"] == "Test Title"
      assert result["description"] == "Test Description"
      assert result["color"] == 0x3498DB
      assert result["url"] == "https://example.com"
      assert result["timestamp"] == "2023-04-15T12:30:45Z"
      assert length(result["fields"]) == 2
      assert Enum.at(result["fields"], 0)["name"] == "Field 1"
      assert Enum.at(result["fields"], 0)["value"] == "Value 1"
      assert Enum.at(result["fields"], 0)["inline"] == true
      assert Enum.at(result["fields"], 1)["name"] == "Field 2"
      assert Enum.at(result["fields"], 1)["value"] == "Value 2"
      assert Enum.at(result["fields"], 1)["inline"] == false
    end
  end

  describe "format_system_status_message/8" do
    test "formats a system status message correctly" do
      # Create test data
      stats = %{
        notifications: %{
          total: 100,
          kills: 50,
          systems: 30,
          characters: 20
        },
        websocket: %{
          connected: true,
          last_message: DateTime.utc_now()
        }
      }

      features_status = %{
        kill_notifications_enabled: true,
        system_tracking_enabled: true,
        character_tracking_enabled: true,
        activity_charts: false
      }

      license_status = %{
        valid: true,
        premium: false
      }

      # 1 day, 1 hour, 1 minute, 30 seconds
      uptime = 86_400 + 3_600 + 60 + 30

      result =
        StructuredFormatter.format_system_status_message(
          "System Status",
          "Current system status report",
          stats,
          uptime,
          features_status,
          license_status,
          # systems_count
          10,
          # characters_count
          5
        )

      # Check that the result has the expected structure
      assert is_map(result)
      assert result.type == :status_notification
      assert result.title == "System Status"
      assert result.description =~ "Current system status"
      assert result.color
      assert result.thumbnail.url
      assert result.footer.text =~ "Wanderer Notifier"

      # Check uptime field
      uptime_field = Enum.find(result.fields, fn field -> field.name == "Uptime" end)
      assert uptime_field
      assert uptime_field.value =~ "1d 1h 1m 30s"

      # Check license field
      license_field = Enum.find(result.fields, fn field -> field.name == "License" end)
      assert license_field
      assert license_field.value =~ "✅"

      # Check systems field
      systems_field = Enum.find(result.fields, fn field -> field.name == "Systems" end)
      assert systems_field
      assert systems_field.value =~ "10"

      # Check characters field
      characters_field = Enum.find(result.fields, fn field -> field.name == "Characters" end)
      assert characters_field
      assert characters_field.value =~ "5"

      # Check notifications field
      notifications_field =
        Enum.find(result.fields, fn field -> field.name == "📊 Notifications" end)

      assert notifications_field
      assert notifications_field.value =~ "Total: **100**"
      assert notifications_field.value =~ "Kills: **50**"
      assert notifications_field.value =~ "Systems: **30**"
      assert notifications_field.value =~ "Characters: **20**"

      # Check features field
      features_field =
        Enum.find(result.fields, fn field -> field.name == "⚙️ Primary Features" end)

      assert features_field
      assert features_field.value =~ "✅ Kill Notifications"
      assert features_field.value =~ "✅ System Notifications"
      assert features_field.value =~ "✅ Character Notifications"
      assert features_field.value =~ "❌ Activity Charts"
    end

    test "handles startup message without uptime" do
      # Create minimal test data
      stats = %{
        notifications: %{
          total: 0,
          kills: 0,
          systems: 0,
          characters: 0
        }
      }

      features_status = %{
        kill_notifications_enabled: true
      }

      license_status = %{
        valid: true,
        premium: false
      }

      result =
        StructuredFormatter.format_system_status_message(
          "WandererNotifier Started",
          "The service has started",
          stats,
          # nil uptime for startup
          nil,
          features_status,
          license_status,
          0,
          0
        )

      # Check startup-specific information
      uptime_field = Enum.find(result.fields, fn field -> field.name == "Uptime" end)
      assert uptime_field
      assert uptime_field.value =~ "Just started"

      license_field = Enum.find(result.fields, fn field -> field.name == "License" end)
      assert license_field
      # Non-premium
      assert license_field.value =~ "✅"
    end
  end
end
