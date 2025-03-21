defmodule WandererNotifier.Notifiers.StructuredFormatter do
  @moduledoc """
  Structured notification formatting utilities for Discord notifications.

  This module provides standardized formatting specifically designed to work with
  the domain data structures like Character, MapSystem, and Killmail.
  It eliminates the complex extraction logic of the original formatter by relying
  on the structured data provided by these schemas.
  """

  require Logger

  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Data.Killmail

  # Color constants for Discord notifications
  # Default blue
  @default_color 0x3498DB
  # Green
  @success_color 0x2ECC71
  # Orange
  @warning_color 0xF39C12
  # Red
  @error_color 0xE74C3C
  # Blue
  @info_color 0x3498DB

  # Wormhole and security colors
  # Blue for Pulsar
  @wormhole_color 0x428BCA
  # Green for highsec
  @highsec_color 0x5CB85C
  # Yellow/orange for lowsec
  @lowsec_color 0xE28A0D
  # Red for nullsec
  @nullsec_color 0xD9534F

  # System notification icons
  # Wormhole icon
  @wormhole_icon "https://images.evetech.net/types/45041/icon"
  # Highsec icon
  @highsec_icon "https://images.evetech.net/types/3802/icon"
  # Lowsec icon
  @lowsec_icon "https://images.evetech.net/types/3796/icon"
  # Nullsec icon
  @nullsec_icon "https://images.evetech.net/types/3799/icon"
  # Default icon
  @default_icon "https://images.evetech.net/types/3802/icon"

  @doc """
  Returns a standardized set of colors for notification embeds.

  ## Returns
    - A map with color constants for various notification types
  """
  def colors do
    %{
      default: @default_color,
      success: @success_color,
      warning: @warning_color,
      error: @error_color,
      info: @info_color,
      wormhole: @wormhole_color,
      highsec: @highsec_color,
      lowsec: @lowsec_color,
      nullsec: @nullsec_color
    }
  end

  @doc """
  Converts a color in one format to Discord format.

  ## Parameters
    - color: The color to convert (atom, integer, or hex string)

  ## Returns
    - The color in Discord format (integer)
  """
  def convert_color(color) when is_atom(color) do
    Map.get(colors(), color, @default_color)
  end

  def convert_color(color) when is_integer(color), do: color

  def convert_color("#" <> hex) do
    {color, _} = Integer.parse(hex, 16)
    color
  end

  def convert_color(_color), do: @default_color

  @doc """
  Creates a standard formatted kill notification embed/attachment from a Killmail struct.
  Returns data in a generic format that can be converted to platform-specific format.

  ## Parameters
    - killmail: The Killmail struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_kill_notification(%Killmail{} = killmail) do
    kill_id = killmail.killmail_id

    # Log the structure of the killmail for debugging
    Logger.debug("[StructuredFormatter] Formatting killmail: #{inspect(killmail, limit: 200)}")

    # Check if we have all required fields
    has_victim = Killmail.get_victim(killmail) != nil
    has_system_name = Map.get(killmail.esi_data || %{}, "solar_system_name") != nil

    Logger.debug(
      "[StructuredFormatter] Killmail has_victim: #{has_victim}, has_system_name: #{has_system_name}"
    )

    # Get victim information
    victim = Killmail.get_victim(killmail) || %{}
    victim_name = Map.get(victim, "character_name", "Unknown Pilot")
    victim_ship = Map.get(victim, "ship_type_name", "Unknown Ship")
    victim_corp = Map.get(victim, "corporation_name", "Unknown Corp")
    victim_alliance = Map.get(victim, "alliance_name")
    victim_ship_type_id = Map.get(victim, "ship_type_id")
    victim_character_id = Map.get(victim, "character_id")

    # Get zkillboard data
    zkb = killmail.zkb || %{}
    kill_value = Map.get(zkb, "totalValue", 0)
    formatted_value = format_isk_value(kill_value)

    # Kill time and system info
    kill_time = Map.get(killmail.esi_data || %{}, "killmail_time")
    system_name = Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")

    # Log the extracted values for debugging
    Logger.debug("[StructuredFormatter] Extracted victim_name: #{victim_name}")
    Logger.debug("[StructuredFormatter] Extracted victim_ship: #{victim_ship}")
    Logger.debug("[StructuredFormatter] Extracted system_name: #{system_name}")

    # Attackers information
    attackers = Map.get(killmail.esi_data || %{}, "attackers", [])
    attackers_count = length(attackers)

    # Final blow details
    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        Map.get(attacker, "final_blow") in [true, "true"]
      end)

    is_npc_kill = Map.get(zkb, "npc", false) == true

    final_blow_details = extract_final_blow_details(final_blow_attacker, is_npc_kill)

    # Build a platform-agnostic structure
    %{
      type: :kill_notification,
      title: "Kill Notification",
      description: "#{victim_name} lost a #{victim_ship} in #{system_name}",
      color: @error_color,
      url: "https://zkillboard.com/kill/#{kill_id}/",
      timestamp: kill_time,
      footer: %{
        text: "Kill ID: #{kill_id}"
      },
      thumbnail: %{
        url:
          if(victim_ship_type_id,
            do: "https://images.evetech.net/types/#{victim_ship_type_id}/render",
            else: nil
          )
      },
      author: %{
        name:
          if(victim_name == "Unknown Pilot" and victim_corp == "Unknown Corp") do
            "Kill in #{system_name}"
          else
            "#{victim_name} (#{victim_corp})"
          end,
        icon_url:
          if(victim_name == "Unknown Pilot" and victim_corp == "Unknown Corp") do
            "https://images.evetech.net/types/30371/icon"
          else
            if(victim_character_id,
              do: "https://imageserver.eveonline.com/Character/#{victim_character_id}_64.jpg",
              else: nil
            )
          end
      },
      fields:
        [
          %{name: "Value", value: formatted_value, inline: true},
          %{name: "Attackers", value: "#{attackers_count}", inline: true},
          %{name: "Final Blow", value: final_blow_details.text, inline: true}
        ] ++
          if(victim_alliance,
            do: [%{name: "Alliance", value: victim_alliance, inline: true}],
            else: []
          )
    }
  end

  @doc """
  Creates a standard formatted new tracked character notification from a Character struct.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_character_notification(%Character{} = character) do
    Logger.info(
      "[StructuredFormatter] Processing Character notification for: #{character.name} (#{character.eve_id})"
    )

    # Log all character fields to diagnose issues
    Logger.info("[StructuredFormatter] Character struct fields:")
    Logger.info("[StructuredFormatter] - name: #{inspect(character.name)}")
    Logger.info("[StructuredFormatter] - eve_id: #{inspect(character.eve_id)}")
    Logger.info("[StructuredFormatter] - corporation_id: #{inspect(character.corporation_id)}")

    Logger.info(
      "[StructuredFormatter] - corporation_ticker: #{inspect(character.corporation_ticker)}"
    )

    Logger.info("[StructuredFormatter] - alliance_id: #{inspect(character.alliance_id)}")
    Logger.info("[StructuredFormatter] - alliance_ticker: #{inspect(character.alliance_ticker)}")
    Logger.info("[StructuredFormatter] - tracked: #{inspect(character.tracked)}")

    # Log the entire struct for comprehensive debugging
    Logger.debug(
      "[StructuredFormatter] Full character struct: #{inspect(character, pretty: true, limit: 10000)}"
    )

    # Build notification structure
    %{
      type: :character_notification,
      title: "New Character Tracked",
      description: "A new character has been added to the tracking list.",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        url: "https://imageserver.eveonline.com/Character/#{character.eve_id}_128.jpg"
      },
      fields:
        [
          %{
            name: "Character",
            value: "[#{character.name}](https://zkillboard.com/character/#{character.eve_id}/)",
            inline: true
          }
        ] ++
          if Character.has_corporation?(character) do
            corporation_link =
              "[#{character.corporation_ticker}](https://zkillboard.com/corporation/#{character.corporation_id}/)"

            Logger.info(
              "[StructuredFormatter] Adding corporation field with value: #{corporation_link}"
            )

            [%{name: "Corporation", value: corporation_link, inline: true}]
          else
            Logger.info("[StructuredFormatter] No corporation data available for inclusion")
            []
          end
    }
  end

  @doc """
  Creates a standard formatted system notification from a MapSystem struct.

  ## Parameters
    - system: The MapSystem struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_system_notification(%MapSystem{} = system) do
    Logger.info(
      "[StructuredFormatter] Processing system notification for: #{system.name} (#{system.solar_system_id})"
    )

    # Validate required fields
    if is_nil(system.solar_system_id) do
      Logger.error("[StructuredFormatter] Missing solar_system_id in MapSystem struct")
      raise "Cannot format system notification: solar_system_id is missing"
    end

    if is_nil(system.name) do
      Logger.error("[StructuredFormatter] Missing name in MapSystem struct")
      raise "Cannot format system notification: name is missing"
    end

    # Log key fields for debugging
    Logger.debug("[StructuredFormatter] System struct fields:")
    Logger.debug("[StructuredFormatter] - solar_system_id: #{system.solar_system_id}")
    Logger.debug("[StructuredFormatter] - name: #{inspect(system.name)}")
    Logger.debug("[StructuredFormatter] - temporary_name: #{inspect(system.temporary_name)}")
    Logger.debug("[StructuredFormatter] - original_name: #{inspect(system.original_name)}")
    Logger.debug("[StructuredFormatter] - type_description: #{inspect(system.type_description)}")
    Logger.debug("[StructuredFormatter] - class_title: #{inspect(system.class_title)}")
    Logger.debug("[StructuredFormatter] - effect_name: #{inspect(system.effect_name)}")
    Logger.debug("[StructuredFormatter] - is_shattered: #{inspect(system.is_shattered)}")
    Logger.debug("[StructuredFormatter] - region_name: #{inspect(system.region_name)}")
    Logger.debug("[StructuredFormatter] - statics: #{inspect(system.statics)}")
    Logger.debug("[StructuredFormatter] - static_details: #{inspect(system.static_details)}")
    Logger.debug("[StructuredFormatter] - system_type: #{inspect(system.system_type)}")

    # Check if the system is a wormhole
    is_wormhole = MapSystem.is_wormhole?(system)
    Logger.debug("[StructuredFormatter] Is wormhole: #{is_wormhole}")

    # Generate the display name for the notification
    display_name = MapSystem.format_display_name(system)
    Logger.debug("[StructuredFormatter] Formatted display name: #{inspect(display_name)}")

    # Generate title and description based on system type
    title = generate_system_title(is_wormhole, system.class_title, system.type_description)
    Logger.debug("[StructuredFormatter] Generated title: #{inspect(title)}")

    description =
      generate_system_description(is_wormhole, system.class_title, system.type_description)

    Logger.debug("[StructuredFormatter] Generated description: #{inspect(description)}")

    # Generate color based on system type
    system_color = determine_system_color(system.type_description, is_wormhole)
    Logger.debug("[StructuredFormatter] Determined system color: #{inspect(system_color)}")

    # Get the system icon
    icon_url = determine_system_icon(is_wormhole, system.type_description, system.sun_type_id)
    Logger.debug("[StructuredFormatter] Determined icon URL: #{inspect(icon_url)}")

    # Format the statics list, preferring static_details if available
    formatted_statics = format_statics_list(system.static_details || system.statics)
    Logger.debug("[StructuredFormatter] Formatted statics: #{inspect(formatted_statics)}")

    # Create a system name with zkillboard link
    system_name_with_link =
      if is_integer(system.solar_system_id) ||
           (is_binary(system.solar_system_id) && Integer.parse(system.solar_system_id) != :error) do
        # For numerical IDs, create a zkillboard link
        system_id_str = to_string(system.solar_system_id)

        # If the system has a temporary_name and original_name, include the original in parentheses
        if system.temporary_name && system.temporary_name != "" && system.original_name &&
             system.original_name != "" do
          "[#{system.temporary_name} (#{system.original_name})](https://zkillboard.com/system/#{system_id_str}/)"
        else
          "[#{system.name}](https://zkillboard.com/system/#{system_id_str}/)"
        end
      else
        # For non-numerical IDs (like temporary IDs), just show the display name without a link
        display_name
      end

    Logger.debug("[StructuredFormatter] System name with link: #{inspect(system_name_with_link)}")

    # Build fields list
    fields = [%{name: "System", value: system_name_with_link, inline: true}]

    # Add shattered field if applicable
    fields =
      if is_wormhole && system.is_shattered do
        fields ++ [%{name: "Shattered", value: "Yes", inline: true}]
      else
        fields
      end

    # Add statics field if applicable for wormhole systems, preferring static_details
    fields =
      if is_wormhole && formatted_statics && formatted_statics != "None" do
        fields ++ [%{name: "Statics", value: formatted_statics, inline: true}]
      else
        fields
      end

    # Add region field if available
    fields =
      if system.region_name do
        encoded_region_name = URI.encode(system.region_name)

        region_link =
          "[#{system.region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"

        fields ++ [%{name: "Region", value: region_link, inline: true}]
      else
        fields
      end

    # Add effect field if available for wormhole systems
    fields =
      if is_wormhole && system.effect_name && system.effect_name != "" do
        fields ++ [%{name: "Effect", value: system.effect_name, inline: true}]
      else
        fields
      end

    # Create the generic notification structure
    %{
      type: :system_notification,
      title: title,
      description: description,
      color: system_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{url: icon_url},
      fields: fields,
      footer: %{
        text: "System ID: #{system.solar_system_id}"
      }
    }
  end

  @doc """
  Converts a generic notification structure to Discord format.

  ## Parameters
    - notification: The generic notification structure

  ## Returns
    - A Discord-specific embed structure
  """
  def to_discord_format(notification) do
    # Convert to Discord embed format
    %{
      "title" => notification.title,
      "description" => notification.description,
      "color" => notification.color,
      "url" => Map.get(notification, :url),
      "timestamp" => Map.get(notification, :timestamp),
      "footer" => Map.get(notification, :footer),
      "thumbnail" => Map.get(notification, :thumbnail),
      "author" => Map.get(notification, :author),
      "fields" =>
        Enum.map(notification.fields || [], fn field ->
          %{
            "name" => field.name,
            "value" => field.value,
            "inline" => Map.get(field, :inline, false)
          }
        end)
    }
  end

  # Helper functions

  # Extracts details about the final blow attacker
  defp extract_final_blow_details(final_blow_attacker, is_npc_kill) do
    if final_blow_attacker do
      # Extract character_id and name
      final_blow_character_id = Map.get(final_blow_attacker, "character_id")

      # Extract character name
      final_blow_name =
        if is_npc_kill do
          "NPC"
        else
          Map.get(final_blow_attacker, "character_name", "Unknown Pilot")
        end

      # Extract ship type
      final_blow_ship = Map.get(final_blow_attacker, "ship_type_name", "Unknown Ship")

      # Create response with appropriate formatting
      if final_blow_character_id && !is_npc_kill do
        # If we have a character ID and it's not an NPC kill, include a zkillboard link
        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: final_blow_character_id,
          text:
            "[#{final_blow_name}](https://zkillboard.com/character/#{final_blow_character_id}/) (#{final_blow_ship})"
        }
      else
        # Otherwise just format the name and ship without a link
        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: nil,
          text: "#{final_blow_name} (#{final_blow_ship})"
        }
      end
    else
      # No final blow attacker found, return default values
      %{
        name: "Unknown Pilot",
        ship: "Unknown Ship",
        character_id: nil,
        text: "Unknown Pilot (Unknown Ship)"
      }
    end
  end

  # Helper to determine system icon URL based on MapSystem data
  defp determine_system_icon(is_wormhole, type_description, _sun_type_id) do
    cond do
      is_wormhole ->
        # For wormhole systems, use the wormhole icon
        @wormhole_icon

      type_description && String.contains?(type_description, "High-sec") ->
        # For high-sec systems, use the high-sec icon
        @highsec_icon

      type_description && String.contains?(type_description, "Low-sec") ->
        # For low-sec systems, use the low-sec icon
        @lowsec_icon

      type_description && String.contains?(type_description, "Null-sec") ->
        # For null-sec systems, use the null-sec icon
        @nullsec_icon

      true ->
        # Default icon for other system types
        @default_icon
    end
  end

  # Helper to determine system color based on type_description and is_wormhole
  defp determine_system_color(type_description, is_wormhole) do
    cond do
      is_wormhole -> @wormhole_color
      type_description && String.contains?(type_description, "High-sec") -> @highsec_color
      type_description && String.contains?(type_description, "Low-sec") -> @lowsec_color
      type_description && String.contains?(type_description, "Null-sec") -> @nullsec_color
      true -> @default_color
    end
  end

  # Generate system title based on system properties
  defp generate_system_title(is_wormhole, class_title, type_description) do
    cond do
      is_wormhole && class_title && class_title != "" ->
        "New #{class_title} System Mapped"

      is_wormhole ->
        "New Wormhole System Mapped"

      type_description && type_description != "" ->
        "New #{type_description} System Mapped"

      true ->
        # Default title if both class_title and type_description are missing
        "New System Mapped"
    end
  end

  # Generate system description based on system properties
  defp generate_system_description(is_wormhole, class_title, type_description) do
    cond do
      is_wormhole && class_title && class_title != "" ->
        "A #{class_title} wormhole system has been discovered and added to the map."

      is_wormhole ->
        "A wormhole system has been discovered and added to the map."

      type_description && type_description != "" ->
        "A #{type_description} system has been discovered and added to the map."

      true ->
        # Default description if both class_title and type_description are missing
        "A new system has been discovered and added to the map."
    end
  end

  # Format a list of statics for system notification with clear error handling
  defp format_statics_list(nil) do
    Logger.debug("[StructuredFormatter.format_statics_list] Nil statics list")
    "None"
  end

  defp format_statics_list([]) do
    Logger.debug("[StructuredFormatter.format_statics_list] Empty statics list")
    "None"
  end

  defp format_statics_list(statics) when is_list(statics) do
    Logger.debug(
      "[StructuredFormatter.format_statics_list] Processing list of #{length(statics)} statics"
    )

    formatted =
      Enum.map(statics, fn static ->
        Logger.debug(
          "[StructuredFormatter.format_statics_list] Formatting static: #{inspect(static)}"
        )

        format_single_static(static)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    if formatted == "" do
      "None"
    else
      formatted
    end
  end

  # Formats a single static wormhole for display
  # Handles both map and struct formats
  defp format_single_static(static) when is_map(static) do
    cond do
      # Handle detailed static info with destination
      Map.has_key?(static, "destination") || Map.has_key?(static, :destination) ->
        name = Map.get(static, "name") || Map.get(static, :name)
        destination = Map.get(static, "destination") || Map.get(static, :destination)
        dest_short = get_in(destination, ["short_name"]) || get_in(destination, [:short_name])

        if name && dest_short do
          "#{name} (#{dest_short})"
        else
          name
        end

      # Handle simple static name
      Map.has_key?(static, "name") || Map.has_key?(static, :name) ->
        Map.get(static, "name") || Map.get(static, :name)

      # Handle string static
      is_binary(static) ->
        static

      true ->
        Logger.warning(
          "[StructuredFormatter.format_single_static] Unrecognized static format: #{inspect(static)}"
        )

        nil
    end
  end

  defp format_single_static(static) when is_binary(static) do
    static
  end

  defp format_single_static(static) do
    Logger.warning(
      "[StructuredFormatter.format_single_static] Unrecognized static format: #{inspect(static)}"
    )

    nil
  end

  # Formats ISK value for display
  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{custom_round(value / 1000)}k ISK"
      true -> "#{custom_round(value / 1_000_000)}M ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

  # Round a float to the nearest integer
  defp custom_round(float) when is_float(float), do: trunc(float + 0.5)
  defp custom_round(int) when is_integer(int), do: int

  # Get application version - first check env var, then Application.spec, fallback to "dev"
  defp get_app_version do
    System.get_env("APP_VERSION") ||
      Application.spec(:wanderer_notifier, :vsn) ||
      "dev"
  end

  @doc """
  Creates a rich formatted status/startup message with enhanced visual elements.

  ## Parameters
    - title: The title for the message (e.g., "WandererNotifier Started" or "Service Status Report")
    - description: Brief description of the message purpose
    - stats: The stats map containing notification counts and websocket info
    - uptime: Optional uptime in seconds (for status messages, nil for startup)
    - features_status: Map of feature statuses
    - license_status: Map with license information
    - systems_count: Number of tracked systems
    - characters_count: Number of tracked characters

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_system_status_message(
        title,
        description,
        stats,
        uptime \\ nil,
        features_status,
        license_status,
        systems_count,
        characters_count
      ) do
    Logger.info("[StructuredFormatter] Creating status message with title: #{title}")

    # Format uptime if provided
    uptime_str =
      if uptime do
        days = div(uptime, 86400)
        hours = div(rem(uptime, 86400), 3600)
        minutes = div(rem(uptime, 3600), 60)
        seconds = rem(uptime, 60)
        "⏱️ #{days}d #{hours}h #{minutes}m #{seconds}s"
      else
        "🚀 Just started"
      end

    is_premium = Map.get(license_status, :premium, false)

    license_icon =
      if license_status.valid do
        if is_premium, do: "💎", else: "✅"
      else
        "❌"
      end

    # Get WebSocket status icon
    websocket_icon =
      if Map.has_key?(stats, :websocket) do
        ws_status = stats.websocket

        if ws_status.connected do
          last_message = ws_status.last_message

          if last_message do
            time_diff = DateTime.diff(DateTime.utc_now(), last_message, :second)

            cond do
              time_diff < 60 -> "🟢"
              time_diff < 300 -> "🟡"
              true -> "🟠"
            end
          else
            "🟡"
          end
        else
          "🔴"
        end
      else
        "❓"
      end

    # Format notification counts
    notification_info =
      if Map.has_key?(stats, :notifications) do
        format_notification_counts(stats.notifications)
      else
        "No notifications sent yet"
      end

    # Extract primary feature statuses
    primary_features = %{
      kill_notifications: Map.get(features_status, :kill_notifications_enabled, true),
      tracked_systems_notifications: Map.get(features_status, :system_tracking_enabled, true),
      tracked_characters_notifications:
        Map.get(features_status, :character_tracking_enabled, true),
      activity_charts: Map.get(features_status, :activity_charts, false)
    }

    # For debugging display
    Logger.debug("[StructuredFormatter] Found feature statuses: #{inspect(features_status)}")
    Logger.debug("[StructuredFormatter] Extracted primary features: #{inspect(primary_features)}")

    # Format primary feature statuses
    formatted_features =
      [
        format_feature_item("Kill Notifications", primary_features.kill_notifications),
        format_feature_item(
          "System Notifications",
          primary_features.tracked_systems_notifications
        ),
        format_feature_item(
          "Character Notifications",
          primary_features.tracked_characters_notifications
        ),
        format_feature_item(
          "Activity Charts",
          primary_features.activity_charts
        )
      ]
      |> Enum.join("\n")

    # Build the response structure
    %{
      type: :status_notification,
      title: title,
      description: "#{description}\n\n**System Status Overview:**",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        # Use the EVE Online logo or similar icon
        url: "https://images.evetech.net/corporations/1000001/logo?size=128"
      },
      footer: %{
        text: "Wanderer Notifier v#{get_app_version()}"
      },
      fields: [
        %{name: "Uptime", value: uptime_str, inline: true},
        %{name: "License", value: license_icon, inline: true},
        %{name: "WebSocket", value: websocket_icon, inline: true},
        %{name: "Systems", value: "🗺️ #{systems_count}", inline: true},
        %{name: "Characters", value: "👤 #{characters_count}", inline: true},
        %{name: "📊 Notifications", value: notification_info, inline: false},
        %{name: "⚙️ Primary Features", value: formatted_features, inline: false}
      ]
    }
  end

  # Helper to format a single feature item
  defp format_feature_item(name, enabled) do
    if enabled do
      "✅ #{name}"
    else
      "❌ #{name}"
    end
  end

  # Helper to format notification counts
  defp format_notification_counts(%{} = notifications) do
    total = Map.get(notifications, :total, 0)
    kills = Map.get(notifications, :kills, 0)
    systems = Map.get(notifications, :systems, 0)
    characters = Map.get(notifications, :characters, 0)

    "Total: **#{total}** (Kills: **#{kills}**, Systems: **#{systems}**, Characters: **#{characters}**)"
  end
end
