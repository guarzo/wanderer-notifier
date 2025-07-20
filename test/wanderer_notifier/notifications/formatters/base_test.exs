defmodule WandererNotifier.Domains.Notifications.Formatters.BaseTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Domains.Notifications.Formatters.Base

  describe "build_notification/1" do
    test "builds notification with required fields" do
      attrs = %{
        type: :test_notification,
        title: "Test Title",
        description: "Test Description"
      }

      result = Base.build_notification(attrs)

      assert result.type == :test_notification
      assert result.title == "Test Title"
      assert result.description == "Test Description"
      # default color
      assert result.color == 0x3498DB
      assert is_binary(result.timestamp)
      assert result.fields == []
    end

    test "builds notification with all optional fields" do
      attrs = %{
        type: :system_notification,
        title: "System Alert",
        description: "New system tracked",
        color: :error,
        fields: [%{name: "System", value: "Jita", inline: true}],
        thumbnail: %{url: "https://example.com/thumb.jpg"},
        author: %{name: "Bot", icon_url: "https://example.com/icon.jpg"},
        footer: %{text: "Footer text"},
        timestamp: "2024-01-01T00:00:00Z",
        url: "https://example.com/notification",
        image: %{url: "https://example.com/image.jpg"}
      }

      result = Base.build_notification(attrs)

      assert result.type == :system_notification
      assert result.title == "System Alert"
      assert result.description == "New system tracked"
      # error color
      assert result.color == 0xD9534F
      assert result.fields == [%{name: "System", value: "Jita", inline: true}]
      assert result.thumbnail == %{url: "https://example.com/thumb.jpg"}
      assert result.author == %{name: "Bot", icon_url: "https://example.com/icon.jpg"}
      assert result.footer == %{text: "Footer text"}
      assert result.timestamp == "2024-01-01T00:00:00Z"
      assert result.url == "https://example.com/notification"
      assert result.image == %{url: "https://example.com/image.jpg"}
    end

    test "removes nil values from result" do
      attrs = %{
        type: :test_notification,
        title: "Test",
        description: "Description",
        thumbnail: nil,
        author: nil
      }

      result = Base.build_notification(attrs)

      refute Map.has_key?(result, :thumbnail)
      refute Map.has_key?(result, :author)
    end

    test "raises when required fields are missing" do
      assert_raise KeyError, fn ->
        Base.build_notification(%{title: "Test"})
      end

      assert_raise KeyError, fn ->
        Base.build_notification(%{type: :test, description: "Test"})
      end
    end
  end

  describe "build_field/3" do
    test "builds basic field" do
      result = Base.build_field("Name", "Value")

      assert result == %{name: "Name", value: "Value", inline: false}
    end

    test "builds inline field" do
      result = Base.build_field("Name", "Value", true)

      assert result == %{name: "Name", value: "Value", inline: true}
    end

    test "converts values to strings safely" do
      result = Base.build_field("Number", 123, true)

      assert result == %{name: "Number", value: "123", inline: true}
    end

    test "handles nil values" do
      result = Base.build_field(nil, nil)

      assert result == %{name: "", value: "", inline: false}
    end
  end

  describe "build_fields/1" do
    test "builds multiple fields from tuples" do
      field_data = [
        {"Character", "John Doe", true},
        {"Corporation", "Test Corp", true},
        {"Description", "Long description"}
      ]

      result = Base.build_fields(field_data)

      assert length(result) == 3
      assert Enum.at(result, 0) == %{name: "Character", value: "John Doe", inline: true}
      assert Enum.at(result, 1) == %{name: "Corporation", value: "Test Corp", inline: true}

      assert Enum.at(result, 2) == %{
               name: "Description",
               value: "Long description",
               inline: false
             }
    end

    test "handles empty list" do
      result = Base.build_fields([])

      assert result == []
    end
  end

  describe "build_thumbnail/1" do
    test "builds thumbnail with URL" do
      result = Base.build_thumbnail("https://example.com/thumb.jpg")

      assert result == %{url: "https://example.com/thumb.jpg"}
    end

    test "returns nil for nil URL" do
      result = Base.build_thumbnail(nil)

      assert result == nil
    end
  end

  describe "build_author/2" do
    test "builds author with name and icon" do
      result = Base.build_author("John Doe", "https://example.com/icon.jpg")

      assert result == %{name: "John Doe", icon_url: "https://example.com/icon.jpg"}
    end

    test "builds author with name only" do
      result = Base.build_author("John Doe")

      assert result == %{name: "John Doe"}
    end

    test "removes nil icon_url" do
      result = Base.build_author("John Doe", nil)

      assert result == %{name: "John Doe"}
      refute Map.has_key?(result, :icon_url)
    end
  end

  describe "build_footer/1" do
    test "builds footer with text" do
      result = Base.build_footer("Footer text")

      assert result == %{text: "Footer text"}
    end

    test "converts values to string" do
      result = Base.build_footer(123)

      assert result == %{text: "123"}
    end
  end

  describe "EVE image URL functions" do
    test "character_portrait_url/2" do
      assert Base.character_portrait_url(123_456_789) ==
               "https://images.evetech.net/characters/123456789/portrait?size=64"

      assert Base.character_portrait_url(123_456_789, 128) ==
               "https://images.evetech.net/characters/123456789/portrait?size=128"
    end

    test "corporation_logo_url/2" do
      assert Base.corporation_logo_url(98_765_432) ==
               "https://images.evetech.net/corporations/98765432/logo?size=64"

      assert Base.corporation_logo_url(98_765_432, 256) ==
               "https://images.evetech.net/corporations/98765432/logo?size=256"
    end

    test "alliance_logo_url/2" do
      assert Base.alliance_logo_url(99_887_766) ==
               "https://images.evetech.net/alliances/99887766/logo?size=64"
    end

    test "type_render_url/2" do
      assert Base.type_render_url(12_345) ==
               "https://images.evetech.net/types/12345/render?size=64"

      assert Base.type_render_url(12_345, 512) ==
               "https://images.evetech.net/types/12345/render?size=512"
    end

    test "type_icon_url/2" do
      assert Base.type_icon_url(54_321) ==
               "https://images.evetech.net/types/54321/icon?size=64"
    end
  end

  describe "zKillboard URL functions" do
    test "zkillboard_character_url/1" do
      assert Base.zkillboard_character_url(123_456_789) ==
               "https://zkillboard.com/character/123456789/"
    end

    test "zkillboard_corporation_url/1" do
      assert Base.zkillboard_corporation_url(98_765_432) ==
               "https://zkillboard.com/corporation/98765432/"
    end

    test "zkillboard_alliance_url/1" do
      assert Base.zkillboard_alliance_url(99_887_766) ==
               "https://zkillboard.com/alliance/99887766/"
    end

    test "zkillboard_system_url/1" do
      assert Base.zkillboard_system_url(30_000_142) ==
               "https://zkillboard.com/system/30000142/"
    end

    test "zkillboard_killmail_url/1" do
      assert Base.zkillboard_killmail_url(87_654_321) ==
               "https://zkillboard.com/kill/87654321/"
    end
  end

  describe "dotlan_region_url/1" do
    test "generates region URL" do
      assert Base.dotlan_region_url("The Forge") ==
               "https://evemaps.dotlan.net/map/The_Forge"
    end

    test "handles spaces in region name" do
      assert Base.dotlan_region_url("Catch") ==
               "https://evemaps.dotlan.net/map/Catch"
    end
  end

  describe "link creation functions" do
    test "create_link/2" do
      result = Base.create_link("Test Link", "https://example.com")

      assert result == "[Test Link](https://example.com)"
    end

    test "create_character_link/2 with ID" do
      result = Base.create_character_link("John Doe", 123_456_789)

      assert result == "[John Doe](https://zkillboard.com/character/123456789/)"
    end

    test "create_character_link/2 without ID" do
      result = Base.create_character_link("John Doe", nil)

      assert result == "John Doe"
    end

    test "create_corporation_link/2 with ID" do
      result = Base.create_corporation_link("Test Corp", 98_765_432)

      assert result == "[Test Corp](https://zkillboard.com/corporation/98765432/)"
    end

    test "create_corporation_link/2 without ID" do
      result = Base.create_corporation_link("Test Corp", nil)

      assert result == "Test Corp"
    end

    test "create_alliance_link/2 with ID" do
      result = Base.create_alliance_link("Test Alliance", 99_887_766)

      assert result == "[Test Alliance](https://zkillboard.com/alliance/99887766/)"
    end

    test "create_alliance_link/2 without ID" do
      result = Base.create_alliance_link("Test Alliance", nil)

      assert result == "Test Alliance"
    end

    test "create_system_link/2 with ID" do
      result = Base.create_system_link("Jita", 30_000_142)

      assert result == "[Jita](https://zkillboard.com/system/30000142/)"
    end

    test "create_system_link/2 without ID" do
      result = Base.create_system_link("Jita", nil)

      assert result == "Jita"
    end
  end

  describe "format_isk_value/1" do
    test "formats billions" do
      assert Base.format_isk_value(1_200_000_000) == "1.2B"
      assert Base.format_isk_value(15_500_000_000) == "15.5B"
    end

    test "formats millions" do
      assert Base.format_isk_value(2_500_000) == "2.5M"
      assert Base.format_isk_value(123_000_000) == "123.0M"
    end

    test "formats thousands" do
      assert Base.format_isk_value(1_500) == "1.5K"
      assert Base.format_isk_value(50_000) == "50.0K"
    end

    test "formats smaller values" do
      assert Base.format_isk_value(999) == "999"
      assert Base.format_isk_value(123.45) == "123"
    end

    test "handles zero and negative" do
      assert Base.format_isk_value(0) == "0"
      assert Base.format_isk_value(-100) == "-100"
    end

    test "handles non-numeric values" do
      assert Base.format_isk_value("invalid") == "0"
      assert Base.format_isk_value(nil) == "0"
    end
  end

  describe "determine_security_color/1" do
    test "determines color by security status" do
      assert Base.determine_security_color(0.8) == :highsec
      assert Base.determine_security_color(0.5) == :highsec
      assert Base.determine_security_color(0.3) == :lowsec
      assert Base.determine_security_color(0.1) == :lowsec
      assert Base.determine_security_color(0.0) == :nullsec
      assert Base.determine_security_color(-1.0) == :wormhole
    end

    test "determines color by type string" do
      assert Base.determine_security_color("Highsec") == :highsec
      assert Base.determine_security_color("Lowsec") == :lowsec
      assert Base.determine_security_color("Nullsec") == :nullsec
      assert Base.determine_security_color("W-Space") == :wormhole
    end

    test "defaults to default for unknown types" do
      assert Base.determine_security_color("Unknown") == :default
      assert Base.determine_security_color(nil) == :default
    end
  end

  describe "get_system_icon/1" do
    test "gets icon by atom" do
      assert Base.get_system_icon(:highsec) == "https://images.evetech.net/types/3802/icon"
      assert Base.get_system_icon(:lowsec) == "https://images.evetech.net/types/3796/icon"
      assert Base.get_system_icon(:nullsec) == "https://images.evetech.net/types/3799/icon"
      assert Base.get_system_icon(:wormhole) == "https://images.evetech.net/types/45041/icon"
    end

    test "gets icon by string" do
      assert Base.get_system_icon("Highsec") == "https://images.evetech.net/types/3802/icon"
      assert Base.get_system_icon("lowsec") == "https://images.evetech.net/types/3796/icon"
      assert Base.get_system_icon("W-Space") == "https://images.evetech.net/types/45041/icon"
      assert Base.get_system_icon("wormhole") == "https://images.evetech.net/types/45041/icon"
    end

    test "defaults to default icon for unknown types" do
      assert Base.get_system_icon("Unknown") == "https://images.evetech.net/types/3802/icon"
      assert Base.get_system_icon(nil) == "https://images.evetech.net/types/3802/icon"
    end
  end

  describe "safe_to_string/1" do
    test "handles nil" do
      assert Base.safe_to_string(nil) == ""
    end

    test "preserves strings" do
      assert Base.safe_to_string("test") == "test"
    end

    test "converts numbers" do
      assert Base.safe_to_string(123) == "123"
      assert Base.safe_to_string(3.14) == "3.14"
    end

    test "converts other types" do
      assert Base.safe_to_string(:atom) == ":atom"
      assert Base.safe_to_string([1, 2, 3]) == "[1, 2, 3]"
    end
  end

  describe "resolve_color/1" do
    test "resolves color atoms" do
      assert Base.resolve_color(:info) == 0x3498DB
      assert Base.resolve_color(:error) == 0xD9534F
      assert Base.resolve_color(:success) == 0x5CB85C
      assert Base.resolve_color(:warning) == 0xE28A0D
      assert Base.resolve_color(:wormhole) == 0x428BCA
    end

    test "resolves hex color strings" do
      assert Base.resolve_color("#FF0000") == 0xFF0000
      assert Base.resolve_color("#3498DB") == 0x3498DB
    end

    test "preserves integer colors" do
      assert Base.resolve_color(0xFF0000) == 0xFF0000
      assert Base.resolve_color(123_456) == 123_456
    end

    test "defaults for invalid colors" do
      assert Base.resolve_color("invalid") == 0x3498DB
      assert Base.resolve_color("#INVALID") == 0x3498DB
      assert Base.resolve_color(nil) == 0x3498DB
    end
  end

  describe "with_error_handling/4" do
    test "executes function successfully" do
      result =
        Base.with_error_handling(__MODULE__, "test operation", %{test: "data"}, fn ->
          "success"
        end)

      assert result == "success"
    end

    test "re-raises exceptions with logging" do
      import ExUnit.CaptureLog

      log =
        capture_log([level: :error], fn ->
          assert_raise RuntimeError, "test error", fn ->
            Base.with_error_handling(__MODULE__, "test operation", %{test: "data"}, fn ->
              raise "test error"
            end)
          end
        end)

      assert log =~ "Error in"
      assert log =~ "test operation"
      assert log =~ "test error"
    end
  end
end
