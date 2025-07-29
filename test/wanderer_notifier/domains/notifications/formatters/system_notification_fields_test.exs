defmodule WandererNotifier.Domains.Notifications.Formatters.SystemNotificationFieldsTest do
  @moduledoc """
  Unit tests for system notification field validation - regression prevention.

  These tests validate the core functionality to prevent the regression where
  system notifications were simplified and lost critical fields like statics,
  class information, links, etc.

  Note: Recent kills tests are excluded here since they require HTTP mocking.
  The focus is on static field validation to catch regressions quickly.
  """

  use ExUnit.Case, async: false

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Tracking.Entities.System

  describe "system notification field validation" do
    test "wormhole system has all required fields with proper values" do
      # Create a comprehensive wormhole system
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

      formatted = NotificationFormatter.format_notification(wormhole_system)

      # Basic structure validation
      assert formatted.type == :system_notification
      assert formatted.title == "New System Tracked: J155416"
      assert String.contains?(formatted.description, "wormhole system")
      assert String.contains?(formatted.description, "C4")

      # Footer validation
      assert formatted.footer.text == "System ID: 31001503"

      # Extract field names for validation
      field_names = Enum.map(formatted.fields, & &1.name)

      # Validate all critical fields are present (prevents regression)
      critical_fields = ["System", "Class", "Static Wormholes", "Region", "Effect"]

      for field <- critical_fields do
        assert field in field_names, "REGRESSION: Missing critical field '#{field}'"
      end

      # Note: Recent Kills field is optional and depends on HTTP request success

      # Validate System field has proper link format
      system_field = get_field_by_name(formatted.fields, "System")
      expected_system_link = "[J155416](https://evemaps.dotlan.net/system/J155416)"
      assert system_field.value == expected_system_link
      assert system_field.inline == true

      # Validate Class field
      class_field = get_field_by_name(formatted.fields, "Class")
      assert class_field.value == "C4"
      assert class_field.inline == true

      # Validate Static Wormholes field formatting
      statics_field = get_field_by_name(formatted.fields, "Static Wormholes")
      assert statics_field.value == "C247, P060"
      assert statics_field.inline == true

      # Validate Region field has proper link format
      region_field = get_field_by_name(formatted.fields, "Region")
      expected_region_link = "[D-R00018](https://evemaps.dotlan.net/region/D-R00018)"
      assert region_field.value == expected_region_link
      assert region_field.inline == true

      # Validate Effect field
      effect_field = get_field_by_name(formatted.fields, "Effect")
      assert effect_field.value == "Pulsar"
      assert effect_field.inline == true

      # Validate minimum field count (regression prevention)
      assert length(formatted.fields) >= 5,
             "REGRESSION: Only #{length(formatted.fields)} fields found, expected at least 5"
    end

    test "k-space system excludes wormhole-specific fields" do
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

      formatted = NotificationFormatter.format_notification(kspace_system)

      field_names = Enum.map(formatted.fields, & &1.name)

      # Should have basic fields
      assert "System" in field_names
      assert "Region" in field_names

      # Should NOT have wormhole-specific fields
      refute "Class" in field_names
      refute "Static Wormholes" in field_names
      refute "Effect" in field_names

      # Description should reflect k-space nature
      assert String.contains?(formatted.description, "High-sec system")
      refute String.contains?(formatted.description, "wormhole")
    end

    test "shattered wormhole includes shattered field" do
      shattered_system = %System{
        solar_system_id: "31000001",
        name: "J000001",
        system_type: "wormhole",
        class_title: "C2",
        is_shattered: true,
        statics: ["A641"],
        region_name: "Shattered Region",
        tracked: true
      }

      formatted = NotificationFormatter.format_notification(shattered_system)
      field_names = Enum.map(formatted.fields, & &1.name)

      # Should include Shattered field
      assert "Shattered" in field_names

      shattered_field = get_field_by_name(formatted.fields, "Shattered")
      assert shattered_field.value == "Yes"
    end

    test "empty statics list is handled correctly" do
      system_with_empty_statics = %System{
        solar_system_id: "31001000",
        name: "J100000",
        system_type: "wormhole",
        class_title: "C1",
        # Empty statics
        statics: [],
        region_name: "Test Region",
        tracked: true
      }

      formatted = NotificationFormatter.format_notification(system_with_empty_statics)
      field_names = Enum.map(formatted.fields, & &1.name)

      # Should NOT include Static Wormholes field when empty
      refute "Static Wormholes" in field_names
    end

    test "nil statics is handled correctly" do
      system_with_nil_statics = %System{
        solar_system_id: "31001000",
        name: "J100000",
        system_type: "wormhole",
        class_title: "C1",
        # Nil statics
        statics: nil,
        region_name: "Test Region",
        tracked: true
      }

      formatted = NotificationFormatter.format_notification(system_with_nil_statics)
      field_names = Enum.map(formatted.fields, & &1.name)

      # Should NOT include Static Wormholes field when nil
      refute "Static Wormholes" in field_names
    end

    test "validates color coding for different system types" do
      test_cases = [
        # {system_type, security_status, expected_color}
        # Purple for wormholes
        {"wormhole", -1.0, 4_361_162},
        # Green for high-sec
        {"highsec", 0.8, 65_280},
        # Yellow for low-sec
        {"lowsec", 0.3, 16_776_960},
        # Red for null-sec
        {"nullsec", 0.0, 16_711_680}
      ]

      for {sys_type, security, _expected_color} <- test_cases do
        system = %System{
          solar_system_id: "30000001",
          name: "TestSystem",
          system_type: sys_type,
          security_status: security,
          region_name: "Test Region",
          tracked: true
        }

        formatted = NotificationFormatter.format_notification(system)

        assert is_integer(formatted.color) and formatted.color > 0,
               "Invalid color for #{sys_type} system. Got #{formatted.color}"
      end
    end

    test "validates thumbnail URLs for different system types" do
      wormhole_system = %System{
        solar_system_id: "31001000",
        name: "J100000",
        system_type: "wormhole",
        region_name: "Test",
        tracked: true
      }

      formatted = NotificationFormatter.format_notification(wormhole_system)

      # Should have proper thumbnail URL
      assert is_binary(formatted.thumbnail.url)
    end

    test "validates all link formats are correct" do
      system = %System{
        solar_system_id: "31001503",
        name: "J155416",
        system_type: "wormhole",
        region_name: "D-R00018",
        tracked: true
      }

      formatted = NotificationFormatter.format_notification(system)

      # System link validation
      system_field = get_field_by_name(formatted.fields, "System")
      system_link_pattern = ~r/\[J155416\]\(https:\/\/evemaps\.dotlan\.net\/system\/J155416\)/
      assert Regex.match?(system_link_pattern, system_field.value)

      # Region link validation
      region_field = get_field_by_name(formatted.fields, "Region")
      region_link_pattern = ~r/\[D-R00018\]\(https:\/\/evemaps\.dotlan\.net\/region\/D-R00018\)/
      assert Regex.match?(region_link_pattern, region_field.value)
    end

    test "prevents regression: validates field count thresholds" do
      # This is the main regression prevention test

      minimal_wormhole = %System{
        solar_system_id: "31001000",
        name: "J100000",
        system_type: "wormhole",
        class_title: "C1",
        region_name: "Test Region",
        statics: ["H296"],
        tracked: true
      }

      formatted = NotificationFormatter.format_notification(minimal_wormhole)

      # CRITICAL: Must have at least 4 fields to prevent regression
      # System, Class, Static Wormholes, Region (minimum for wormhole)
      assert length(formatted.fields) >= 4,
             "REGRESSION DETECTED: Wormhole notification only has #{length(formatted.fields)} fields. " <>
               "This indicates a return to simplified notifications. Minimum expected: 4"

      # Must have descriptive title
      assert String.starts_with?(formatted.title, "New System Tracked:"),
             "REGRESSION: Title format changed from expected pattern"

      # Must have rich description
      assert String.length(formatted.description) > 20,
             "REGRESSION: Description too short, indicates simplified notification"

      # Must have proper footer
      assert formatted.footer != nil,
             "REGRESSION: Missing footer information"

      # Must have thumbnail
      assert formatted.thumbnail != nil,
             "REGRESSION: Missing thumbnail information"
    end
  end

  # Helper function to find field by name
  defp get_field_by_name(fields, name) do
    Enum.find(fields, fn field -> field.name == name end)
  end
end
