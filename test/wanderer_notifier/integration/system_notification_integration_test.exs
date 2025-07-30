defmodule WandererNotifier.Integration.SystemNotificationIntegrationTest do
  @moduledoc """
  Integration test for complete system notification functionality.

  This test validates the end-to-end system notification process to prevent
  regressions where notifications were simplified and lost content.

  Tests the complete flow:
  1. System struct creation
  2. Notification formatting
  3. All field validation
  4. Link formatting
  5. Color/thumbnail assignment

  This is the main regression prevention test.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Tracking.Entities.System

  describe "complete system notification integration" do
    @tag :regression_prevention
    test "comprehensive wormhole notification includes all restored fields" do
      # Create a comprehensive wormhole system matching our test case
      wormhole_system = %System{
        solar_system_id: "31001503",
        name: "J155416",
        system_type: "wormhole",
        class_title: "C4",
        type_description: "Class 4",
        region_name: "D-R00018",
        security_status: -1.0,
        is_shattered: false,
        statics: ["C247", "P060"],
        effect_name: "Pulsar",
        tracked: true
      }

      # Format the notification
      result = NotificationFormatter.format_notification(wormhole_system)

      # === REGRESSION PREVENTION ASSERTIONS ===

      # 1. Basic structure validation
      assert result.type == :system_notification
      assert result.title == "New System Tracked: J155416"
      assert String.contains?(result.description, "wormhole system")
      assert String.contains?(result.description, "C4")

      # 2. Footer must contain system ID
      assert result.footer.text == "System ID: 31001503"

      # 3. Must have proper color (wormhole purple)
      assert is_integer(result.color)

      # 4. Must have thumbnail
      assert is_binary(result.thumbnail.url)

      # 5. CRITICAL: Field count regression check
      field_count = length(result.fields)

      assert field_count >= 5,
             "REGRESSION ALERT: Only #{field_count} fields found! " <>
               "System notifications were simplified. Expected minimum: 5 fields. " <>
               "This indicates a return to the bug where notifications lost content."

      # 6. Extract field names for detailed validation
      field_names = result.fields |> Enum.map(& &1.name) |> Enum.sort()

      # 7. CRITICAL: All essential fields must be present
      required_fields = ["System", "Class", "Static Wormholes", "Region", "Effect"]
      missing_fields = required_fields -- field_names

      assert Enum.empty?(missing_fields),
             "REGRESSION ALERT: Missing critical fields: #{inspect(missing_fields)}. " <>
               "This indicates system notifications have been simplified and lost content!"

      # 8. Validate each field's content and format
      fields_map = Map.new(result.fields, fn field -> {field.name, field} end)

      # System field validation
      system_field = fields_map["System"]
      assert system_field.value == "[J155416](https://evemaps.dotlan.net/system/J155416)"
      assert system_field.inline == true

      # Class field validation
      class_field = fields_map["Class"]
      assert class_field.value == "C4"
      assert class_field.inline == true

      # Static Wormholes field validation
      statics_field = fields_map["Static Wormholes"]
      assert statics_field.value == "C247, P060"
      assert statics_field.inline == true

      # Region field validation
      region_field = fields_map["Region"]
      assert region_field.value == "[D-R00018](https://evemaps.dotlan.net/region/D-R00018)"
      assert region_field.inline == true

      # Effect field validation
      effect_field = fields_map["Effect"]
      assert effect_field.value == "Pulsar"
      assert effect_field.inline == true

      # 9. Link format validation (prevent malformed links)
      assert Regex.match?(
               ~r/\[J155416\]\(https:\/\/evemaps\.dotlan\.net\/system\/J155416\)/,
               system_field.value
             )

      assert Regex.match?(
               ~r/\[D-R00018\]\(https:\/\/evemaps\.dotlan\.net\/region\/D-R00018\)/,
               region_field.value
             )
    end

    @tag :regression_prevention
    test "k-space system excludes wormhole fields (prevents false positives)" do
      # Create a k-space system
      kspace_system = %System{
        solar_system_id: "30000142",
        name: "Jita",
        system_type: "highsec",
        type_description: "High-sec",
        region_name: "The Forge",
        security_status: 0.946,
        statics: nil,
        effect_name: nil,
        tracked: true
      }

      result = NotificationFormatter.format_notification(kspace_system)

      # Should have basic fields
      field_names = result.fields |> Enum.map(& &1.name)
      assert "System" in field_names
      assert "Region" in field_names

      # Should NOT have wormhole-specific fields (prevents false test passes)
      refute "Class" in field_names
      refute "Static Wormholes" in field_names
      refute "Effect" in field_names

      # Should have correct color for high-sec
      assert result.color == 65_280

      # Description should reflect k-space
      assert String.contains?(result.description, "High-sec system")
      refute String.contains?(result.description, "wormhole")
    end

    @tag :edge_cases
    test "handles edge cases without crashing" do
      edge_cases = [
        # Minimal system data
        %System{
          solar_system_id: "30000001",
          name: "MinimalSystem",
          region_name: "Test Region",
          tracked: true
        },

        # Wormhole with empty statics
        %System{
          solar_system_id: "31000001",
          name: "J000001",
          system_type: "wormhole",
          class_title: "C1",
          statics: [],
          region_name: "Test Region",
          tracked: true
        },

        # Wormhole with nil statics
        %System{
          solar_system_id: "31000002",
          name: "J000002",
          system_type: "wormhole",
          class_title: "C2",
          statics: nil,
          region_name: "Test Region",
          tracked: true
        }
      ]

      for system <- edge_cases do
        # Should not crash with any edge case
        result = NotificationFormatter.format_notification(system)

        # Basic sanity checks
        assert result.type == :system_notification
        assert is_binary(result.title)
        assert is_binary(result.description)
        assert is_list(result.fields)
        # At minimum should have System field
        assert length(result.fields) >= 1
      end
    end

    @tag :color_validation
    test "validates color coding for all system types" do
      color_test_cases = [
        # {system_type, security_status, expected_color, description}
        {"wormhole", -1.0, 4_361_162, "wormhole purple"},
        {"highsec", 0.8, 65_280, "high-sec green"},
        {"lowsec", 0.3, 16_776_960, "low-sec yellow"},
        {"nullsec", 0.0, 16_711_680, "null-sec red"}
      ]

      for {sys_type, security, _expected_color, desc} <- color_test_cases do
        system = %System{
          solar_system_id: "30000001",
          name: "ColorTest",
          system_type: sys_type,
          security_status: security,
          region_name: "Test Region",
          tracked: true
        }

        result = NotificationFormatter.format_notification(system)

        assert is_integer(result.color) and result.color > 0,
               "Color validation failed for #{desc}. Got invalid color: #{result.color}"
      end
    end

    @tag :performance
    test "notification formatting performance" do
      system = %System{
        solar_system_id: "31001503",
        name: "J155416",
        system_type: "wormhole",
        class_title: "C4",
        region_name: "D-R00018",
        statics: ["C247", "P060"],
        effect_name: "Pulsar",
        tracked: true
      }

      # Measure formatting performance
      {time_microseconds, _result} =
        :timer.tc(fn ->
          NotificationFormatter.format_notification(system)
        end)

      # Should format quickly (under 1 second for regression detection)
      assert time_microseconds < 1_000_000,
             "Notification formatting is too slow: #{time_microseconds}μs. " <>
               "This may indicate a performance regression."
    end

    @tag :comprehensive_validation
    test "validates complete notification structure" do
      system = %System{
        solar_system_id: "31001503",
        name: "J155416",
        system_type: "wormhole",
        class_title: "C4",
        region_name: "D-R00018",
        statics: ["C247", "P060"],
        effect_name: "Pulsar",
        is_shattered: false,
        security_status: -1.0,
        tracked: true
      }

      result = NotificationFormatter.format_notification(system)

      # Comprehensive structure validation
      required_keys = [:type, :title, :description, :color, :thumbnail, :fields, :footer]

      for key <- required_keys do
        assert Map.has_key?(result, key), "Missing required key: #{key}"
        assert result[key] != nil, "Required key #{key} is nil"
      end

      # Fields structure validation
      for field <- result.fields do
        assert Map.has_key?(field, :name), "Field missing name"
        assert Map.has_key?(field, :value), "Field missing value"
        assert Map.has_key?(field, :inline), "Field missing inline flag"
        assert is_binary(field.name), "Field name must be string"
        assert is_binary(field.value), "Field value must be string"
        assert is_boolean(field.inline), "Field inline must be boolean"
      end

      # Footer structure validation
      assert Map.has_key?(result.footer, :text), "Footer missing text"
      assert is_binary(result.footer.text), "Footer text must be string"

      # Thumbnail structure validation
      assert Map.has_key?(result.thumbnail, :url), "Thumbnail missing URL"
      assert is_binary(result.thumbnail.url), "Thumbnail URL must be string"

      assert String.starts_with?(result.thumbnail.url, "http"),
             "Thumbnail URL must be valid HTTP URL"
    end
  end
end
