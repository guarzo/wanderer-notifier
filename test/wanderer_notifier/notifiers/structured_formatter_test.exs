defmodule WandererNotifier.Notifiers.StructuredFormatterTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Api.ESI.ServiceMock, as: ESIServiceMock
  alias WandererNotifier.Api.ZKill.ServiceMock, as: ZKillServiceMock
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Notifiers.Formatters.Common, as: CommonFormatter

  # Set up mocks for the test
  setup :verify_on_exit!

  setup do
    # Configure application to use mocks
    Application.put_env(:wanderer_notifier, :zkill_service, ZKillServiceMock)
    Application.put_env(:wanderer_notifier, :esi_service, ESIServiceMock)

    # Set up expectations for the ESI service mock
    stub(ESIServiceMock, :get_killmail, fn _kill_id, _hash ->
      {:ok,
       %{
         "killmail_id" => 12_345,
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 93_265_357,
           "ship_type_id" => 587
         },
         "attackers" => [
           %{
             "character_id" => 93_898_784,
             "ship_type_id" => 11_567
           }
         ]
       }}
    end)

    # Set up expectations for the ZKill service mock
    stub(ZKillServiceMock, :get_single_killmail, fn _kill_id ->
      {:ok,
       %{
         "killmail_id" => 12_345,
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 93_265_357,
           "ship_type_id" => 587
         },
         "attackers" => [
           %{
             "character_id" => 93_898_784,
             "ship_type_id" => 11_567
           }
         ]
       }}
    end)

    # Add stub for ZKill service get_system_kills
    stub(ZKillServiceMock, :get_system_kills, fn _system_id, _limit ->
      {:ok,
       [
         %{
           "killmail_id" => 12_345,
           "zkb" => %{
             "totalValue" => 1_000_000.0,
             "points" => 1,
             "hash" => "abc123"
           }
         }
       ]}
    end)

    # Set up expectations for the ESI service mock
    stub(ESIServiceMock, :get_character_info, fn _character_id ->
      {:ok, %{"name" => "Test Character"}}
    end)

    stub(ESIServiceMock, :get_type_info, fn _type_id ->
      {:ok, %{"name" => "Test Ship"}}
    end)

    stub(ESIServiceMock, :get_ship_type_name, fn _ship_type_id ->
      {:ok, %{"name" => "Test Ship"}}
    end)

    # Return an empty context
    :ok
  end

  describe "colors/0" do
    test "returns a map of color constants" do
      colors = CommonFormatter.colors()
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
      assert CommonFormatter.convert_color(:default) == CommonFormatter.colors().default
      assert CommonFormatter.convert_color(:success) == CommonFormatter.colors().success
      assert CommonFormatter.convert_color(:warning) == CommonFormatter.colors().warning
      assert CommonFormatter.convert_color(:error) == CommonFormatter.colors().error
      assert CommonFormatter.convert_color(:info) == CommonFormatter.colors().info
    end

    test "returns integer color values unchanged" do
      assert CommonFormatter.convert_color(0x3498DB) == 0x3498DB
      assert CommonFormatter.convert_color(16_711_680) == 16_711_680
    end

    test "converts hex strings to integer values" do
      assert CommonFormatter.convert_color("#FF0000") == 0xFF0000
      assert CommonFormatter.convert_color("#00FF00") == 0x00FF00
      assert CommonFormatter.convert_color("#0000FF") == 0x0000FF
    end

    test "returns default color for invalid inputs" do
      default_color = CommonFormatter.colors().default
      assert CommonFormatter.convert_color(nil) == default_color
      assert CommonFormatter.convert_color("invalid") == default_color
      assert CommonFormatter.convert_color([]) == default_color
    end
  end

  describe "format_kill_notification/1" do
    test "formats a killmail notification correctly" do
      # Create a test killmail using the proper struct
      killmail = %Killmail{
        killmail_id: "12345",
        zkb: %{
          "totalValue" => 1_000_000.0,
          "points" => 1
        },
        esi_data: %{
          "killmail_id" => 12_345,
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => 93_265_357,
            "ship_type_id" => 587
          },
          "attackers" => [
            %{
              "character_id" => 93_898_784,
              "ship_type_id" => 11_567
            }
          ]
        }
      }

      # Format the notification
      result = CommonFormatter.format_kill_notification(killmail)

      # Assert the result structure
      assert is_map(result)
      assert result.type == :kill_notification
      assert result.title == "Kill Notification"
      assert result.description =~ "lost"
      assert result.color
      assert result.url =~ "zkillboard.com/kill/12345"
      assert result.thumbnail.url =~ "images.evetech.net"
      assert is_list(result.fields)
      assert length(result.fields) > 0
    end

    test "handles killmail with missing or partial data" do
      # Create a test killmail with minimal data using the proper struct
      killmail = %Killmail{
        killmail_id: "12345",
        zkb: %{
          "totalValue" => 1_000_000.0,
          "points" => 1
        },
        esi_data: %{
          "killmail_id" => 12_345,
          "solar_system_id" => 30_000_142,
          "victim" => %{},
          "attackers" => []
        }
      }

      # Format the notification
      result = CommonFormatter.format_kill_notification(killmail)

      # Assert the result structure
      assert is_map(result)
      assert result.type == :kill_notification
      assert result.title == "Kill Notification"
      assert result.description =~ "Unknown Pilot"
      assert result.color
      assert result.url =~ "zkillboard.com/kill/12345"
      assert result.thumbnail
      assert is_list(result.fields)
      assert length(result.fields) > 0
    end
  end

  describe "format_character_notification/1" do
    test "handles character without corporation data" do
      # Removed: Character struct no longer exists in the codebase
    end
  end

  describe "format_system_notification/1" do
    test "formats a wormhole system notification correctly" do
      # Removed: MapSystem struct no longer exists in the codebase
    end

    test "formats a k-space system notification correctly" do
      # Removed: MapSystem struct no longer exists in the codebase
    end

    test "raises for system without required fields" do
      # Removed: MapSystem struct no longer exists in the codebase
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

      result = CommonFormatter.to_discord_format(notification)

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
        CommonFormatter.format_system_status_message(
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
        CommonFormatter.format_system_status_message(
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
