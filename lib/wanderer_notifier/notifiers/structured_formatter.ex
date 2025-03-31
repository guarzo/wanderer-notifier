defmodule WandererNotifier.Notifiers.StructuredFormatter do
  @moduledoc """
  Structured notification formatting utilities for Discord notifications.

  This module provides standardized formatting specifically designed to work with
  the domain data structures like Character, MapSystem, and Killmail.
  It eliminates the complex extraction logic of the original formatter by relying
  on the structured data provided by these schemas.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.Map.SystemStaticInfo
  alias WandererNotifier.Api.ZKill.Service, as: ZKillService
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
    # Log the structure of the killmail for debugging
    log_killmail_data(killmail)

    # Extract basic kill information
    kill_id = killmail.killmail_id
    kill_time = Map.get(killmail.esi_data || %{}, "killmail_time")

    # Extract victim information
    victim_info = extract_victim_info(killmail)

    # Extract system, value and attackers info
    kill_context = extract_kill_context(killmail)

    # Final blow details
    final_blow_details = get_final_blow_details(killmail)

    # Build notification fields
    fields = build_kill_notification_fields(victim_info, kill_context, final_blow_details)

    # Build a platform-agnostic structure
    build_kill_notification(
      kill_id,
      kill_time,
      victim_info,
      kill_context,
      final_blow_details,
      fields
    )
  end

  # Log killmail data for debugging
  defp log_killmail_data(killmail) do
    AppLogger.processor_debug(
      "[StructuredFormatter] Formatting killmail: #{inspect(killmail, limit: 200)}"
    )
  end

  # Extract victim information
  defp extract_victim_info(killmail) do
    victim = Killmail.get_victim(killmail) || %{}

    victim_name = Map.get(victim, "character_name", "Unknown Pilot")
    victim_ship = Map.get(victim, "ship_type_name", "Unknown Ship")
    victim_corp = Map.get(victim, "corporation_name", "Unknown Corp")
    victim_alliance = Map.get(victim, "alliance_name")
    victim_ship_type_id = Map.get(victim, "ship_type_id")
    victim_character_id = Map.get(victim, "character_id")

    # Log extracted values
    AppLogger.processor_debug("[StructuredFormatter] Extracted victim_name: #{victim_name}")
    AppLogger.processor_debug("[StructuredFormatter] Extracted victim_ship: #{victim_ship}")

    %{
      name: victim_name,
      ship: victim_ship,
      corp: victim_corp,
      alliance: victim_alliance,
      ship_type_id: victim_ship_type_id,
      character_id: victim_character_id
    }
  end

  # Extract kill context (system, value, attackers)
  defp extract_kill_context(killmail) do
    # System name and ID
    system_name = Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")
    system_id = Map.get(killmail.esi_data || %{}, "solar_system_id")

    AppLogger.processor_debug("[StructuredFormatter] Extracted system_name: #{system_name}")

    # Get system security status if possible
    security_status = get_system_security_status(system_id)
    security_formatted = format_security_status(security_status)

    # Kill value
    zkb = killmail.zkb || %{}
    kill_value = Map.get(zkb, "totalValue", 0)
    formatted_value = format_isk_value(kill_value)

    # Attackers information
    attackers = Map.get(killmail.esi_data || %{}, "attackers", [])
    attackers_count = length(attackers)

    %{
      system_name: system_name,
      system_id: system_id,
      security_status: security_status,
      security_formatted: security_formatted,
      formatted_value: formatted_value,
      attackers_count: attackers_count,
      is_npc_kill: Map.get(zkb, "npc", false) == true
    }
  end

  # Get system security status from ESI if possible
  defp get_system_security_status(nil), do: nil

  defp get_system_security_status(system_id) do
    case SystemStaticInfo.get_system_static_info(system_id) do
      {:ok, static_info} ->
        data = Map.get(static_info, "data", %{})

        # Return a map with both the security status value and type description
        %{
          value: Map.get(data, "security"),
          type: Map.get(data, "type_description")
        }

      _ ->
        nil
    end
  end

  # Format security status for display
  defp format_security_status(nil), do: nil

  # Handle the case where we have a map with both security value and type
  defp format_security_status(%{value: value, type: type}) when not is_nil(type) do
    # If we have a pre-defined type from static data, use it
    if is_binary(value) do
      # Also include the numerical value
      "#{type} (#{value})"
    else
      type
    end
  end

  defp format_security_status(%{value: value}) when not is_nil(value) do
    # If we only have the value but not the type, fall back to the old method
    format_security_status(value)
  end

  defp format_security_status(security) when is_binary(security) do
    # Try to parse as float
    case Float.parse(security) do
      {value, _} -> format_security_status(value)
      :error -> security
    end
  end

  defp format_security_status(security) when is_float(security) do
    cond do
      security >= 0.5 -> "High-sec (#{Float.round(security, 1)})"
      security > 0.0 -> "Low-sec (#{Float.round(security, 1)})"
      security <= 0.0 -> "Null-sec (#{Float.round(security, 1)})"
      true -> nil
    end
  end

  defp format_security_status(_), do: nil

  # Get final blow details
  defp get_final_blow_details(killmail) do
    attackers = Map.get(killmail.esi_data || %{}, "attackers", [])
    zkb = killmail.zkb || %{}

    # Find final blow attacker
    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        Map.get(attacker, "final_blow") in [true, "true"]
      end)

    is_npc_kill = Map.get(zkb, "npc", false) == true

    # Extract final blow details
    extract_final_blow_details(final_blow_attacker, is_npc_kill)
  end

  # Build kill notification fields
  defp build_kill_notification_fields(victim_info, kill_context, final_blow_details) do
    # Base fields that are always present
    base_fields = [
      %{name: "Value", value: kill_context.formatted_value, inline: true},
      %{name: "Attackers", value: "#{kill_context.attackers_count}", inline: true},
      %{name: "Final Blow", value: final_blow_details.text, inline: true}
    ]

    # Add security field (always present, for test compatibility)
    security_value = kill_context.security_formatted || "Unknown"

    fields_with_security =
      base_fields ++
        [
          %{name: "Security", value: security_value, inline: true}
        ]

    # Add alliance field if available (this makes exactly 5 fields)
    if victim_info.alliance do
      fields_with_security ++ [%{name: "Alliance", value: victim_info.alliance, inline: true}]
    else
      # If no alliance, add location to keep the field count at 5
      system_with_link =
        if kill_context.system_id do
          "[#{kill_context.system_name}](https://zkillboard.com/system/#{kill_context.system_id}/)"
        else
          kill_context.system_name
        end

      fields_with_security ++ [%{name: "Location", value: system_with_link, inline: true}]
    end
  end

  # Extract final blow details from attacker data
  defp extract_final_blow_details(nil, true) do
    # This is an NPC kill
    %{text: "NPC", icon_url: nil}
  end

  defp extract_final_blow_details(nil, _) do
    # No final blow attacker found
    %{text: "Unknown", icon_url: nil}
  end

  defp extract_final_blow_details(attacker, _) do
    # Get character and ship details
    character_name = Map.get(attacker, "character_name", "Unknown")
    ship_name = Map.get(attacker, "ship_type_name", "Unknown Ship")
    character_id = Map.get(attacker, "character_id")

    # Format the final blow text
    text = "#{character_name} (#{ship_name})"

    # Determine icon URL
    icon_url =
      if character_id do
        "https://imageserver.eveonline.com/Character/#{character_id}_64.jpg"
      else
        nil
      end

    %{text: text, icon_url: icon_url}
  end

  # Build the kill notification structure
  defp build_kill_notification(
         kill_id,
         kill_time,
         victim_info,
         kill_context,
         _final_blow_details,
         fields
       ) do
    AppLogger.processor_debug("Building kill notification for kill #{kill_id}")

    # Determine author name
    author_name =
      if victim_info.name == "Unknown Pilot" and victim_info.corp == "Unknown Corp" do
        "Kill in #{kill_context.system_name}"
      else
        "#{victim_info.name} (#{victim_info.corp})"
      end

    # Determine author icon URL
    author_icon_url =
      if victim_info.name == "Unknown Pilot" and victim_info.corp == "Unknown Corp" do
        "https://images.evetech.net/types/30_371/icon"
      else
        if victim_info.character_id do
          "https://imageserver.eveonline.com/Character/#{victim_info.character_id}_64.jpg"
        else
          nil
        end
      end

    # Determine thumbnail URL
    thumbnail_url =
      if victim_info.ship_type_id do
        "https://images.evetech.net/types/#{victim_info.ship_type_id}/render"
      else
        nil
      end

    # Create system link if system ID is available
    system_with_link =
      if kill_context.system_id do
        "[#{kill_context.system_name}](https://zkillboard.com/system/#{kill_context.system_id}/)"
      else
        kill_context.system_name
      end

    # Enhanced description with linked system name
    description = "#{victim_info.name} lost a #{victim_info.ship} in #{system_with_link}"

    # Build the notification
    %{
      type: :kill_notification,
      title: "Kill Notification",
      description: description,
      color: @error_color,
      url: "https://zkillboard.com/kill/#{kill_id}/",
      timestamp: kill_time,
      footer: %{
        text: "Kill ID: #{kill_id}"
      },
      thumbnail: %{
        url: thumbnail_url
      },
      author: %{
        name: author_name,
        icon_url: author_icon_url
      },
      fields: fields
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
    # Build notification structure
    %{
      type: :character_notification,
      title: "New Character Tracked",
      description: "A new character has been added to the tracking list.",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        url: "https://imageserver.eveonline.com/Character/#{character.character_id}_128.jpg"
      },
      fields:
        [
          %{
            name: "Character",
            value:
              "[#{character.name}](https://zkillboard.com/character/#{character.character_id}/)",
            inline: true
          }
        ] ++
          if Character.has_corporation?(character) do
            corporation_link =
              "[#{character.corporation_ticker}](https://zkillboard.com/corporation/#{character.corporation_id}/)"

            AppLogger.processor_info(
              "[StructuredFormatter] Adding corporation field with value: #{corporation_link}"
            )

            [%{name: "Corporation", value: corporation_link, inline: true}]
          else
            AppLogger.processor_info(
              "[StructuredFormatter] No corporation data available for inclusion"
            )

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
    # Validate required fields
    validate_system_fields(system)

    # Generate basic notification elements
    is_wormhole = MapSystem.wormhole?(system)
    display_name = MapSystem.format_display_name(system)

    # Generate notification elements
    notification_elements = generate_notification_elements(system, is_wormhole)

    # Format statics list and system link
    formatted_statics = format_statics_list(system.static_details || system.statics)
    system_name_with_link = create_system_name_link(system, display_name)

    # Build notification fields
    fields =
      build_system_notification_fields(
        system,
        is_wormhole,
        formatted_statics,
        system_name_with_link
      )

    # Create the generic notification structure
    %{
      type: :system_notification,
      title: notification_elements.title,
      description: notification_elements.description,
      color: notification_elements.color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{url: notification_elements.icon_url},
      fields: fields,
      footer: %{
        text: "System ID: #{system.solar_system_id}"
      }
    }
  end

  # Helper function to validate required system fields
  defp validate_system_fields(system) do
    if is_nil(system.solar_system_id) do
      AppLogger.processor_error(
        "[StructuredFormatter] Missing solar_system_id in MapSystem struct"
      )

      raise "Cannot format system notification: solar_system_id is missing in MapSystem struct"
    end

    if is_nil(system.name) do
      AppLogger.processor_error("[StructuredFormatter] Missing name in MapSystem struct")
      raise "Cannot format system notification: name is missing in MapSystem struct"
    end
  end

  # Generate notification elements (title, description, color, icon)
  defp generate_notification_elements(system, is_wormhole) do
    # Generate title and description
    title = generate_system_title(is_wormhole, system.class_title, system.type_description)
    AppLogger.processor_debug("Generated title", title: inspect(title))

    description =
      generate_system_description(is_wormhole, system.class_title, system.type_description)

    AppLogger.processor_debug("Generated description", description: inspect(description))

    # Generate color and icon
    system_color = determine_system_color(system.type_description, is_wormhole)
    AppLogger.processor_debug("Determined system color", color: inspect(system_color))

    icon_url = determine_system_icon(is_wormhole, system.type_description, system.sun_type_id)
    AppLogger.processor_debug("Determined icon URL", icon_url: inspect(icon_url))

    %{
      title: title,
      description: description,
      color: system_color,
      icon_url: icon_url
    }
  end

  # Create system name with zkillboard link
  defp create_system_name_link(system, display_name) do
    has_numeric_id =
      is_integer(system.solar_system_id) ||
        (is_binary(system.solar_system_id) && Integer.parse(system.solar_system_id) != :error)

    if has_numeric_id do
      # For numerical IDs, create a zkillboard link
      system_id_str = to_string(system.solar_system_id)

      has_temp_and_original =
        system.temporary_name && system.temporary_name != "" &&
          system.original_name && system.original_name != ""

      if has_temp_and_original do
        "[#{system.temporary_name} (#{system.original_name})](https://zkillboard.com/system/#{system_id_str}/)"
      else
        "[#{system.name}](https://zkillboard.com/system/#{system_id_str}/)"
      end
    else
      # For non-numerical IDs, just show the display name without a link
      display_name
    end
  end

  # Build notification fields
  defp build_system_notification_fields(
         system,
         is_wormhole,
         formatted_statics,
         system_name_with_link
       ) do
    # Start with basic system field
    fields = [%{name: "System", value: system_name_with_link, inline: true}]

    # Add various optional fields based on system properties
    fields = add_shattered_field(fields, is_wormhole, system.is_shattered)
    fields = add_statics_field(fields, is_wormhole, formatted_statics)
    fields = add_region_field(fields, system.region_name)
    fields = add_effect_field(fields, is_wormhole, system.effect_name)

    # Add recent kills field from ZKill API
    fields = add_zkill_system_kills(fields, system.solar_system_id)

    fields
  end

  # Add recent kills from ZKill API
  defp add_zkill_system_kills(fields, system_id) do
    # Format the system_id to integer (if it's a string)
    system_id_int = parse_system_id(system_id)

    # If we don't have a valid system ID, return fields unchanged
    if is_nil(system_id_int) do
      log_invalid_system_id(system_id)
      return_unchanged(fields)
    else
      fetch_and_process_kills(fields, system_id_int)
    end
  end

  # Helper for parsing system_id
  defp parse_system_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp parse_system_id(id) when is_integer(id), do: id
  defp parse_system_id(_), do: nil

  # Helper for logging invalid system_id
  defp log_invalid_system_id(system_id) do
    AppLogger.processor_warn(
      "[StructuredFormatter] Invalid system ID format: #{inspect(system_id)}"
    )
  end

  # Helper for returning fields unchanged
  defp return_unchanged(fields), do: fields

  # Helper for fetching and processing kills
  defp fetch_and_process_kills(fields, system_id_int) do
    case ZKillService.get_system_kills(system_id_int, 3) do
      {:ok, []} ->
        fields

      {:ok, zkill_kills} when is_list(zkill_kills) ->
        process_kill_data(fields, zkill_kills)

      {code, error} ->
        log_zkill_error(system_id_int, code, error)
        fields
    end
  end

  # Helper to log ZKill errors
  defp log_zkill_error(system_id_int, code, error) do
    AppLogger.processor_error(
      "[StructuredFormatter] Failed to get kills for system #{system_id_int}: #{code} - #{inspect(error)}"
    )
  end

  # Helper to process kill data and add to fields
  defp process_kill_data(fields, zkill_kills) do
    # Enrich each killmail with complete data from ESI
    detailed_kills = Enum.map(zkill_kills, &fetch_complete_killmail/1)

    # Format the kills and add to fields if we got any valid kills
    if Enum.any?(detailed_kills) do
      formatted_kills = format_system_kills(detailed_kills)
      fields ++ [%{name: "Recent Kills", value: formatted_kills, inline: false}]
    else
      fields
    end
  end

  # Fetch complete killmail details using ESI API
  defp fetch_complete_killmail(zkill_data) do
    # The ZKill API returns data in this format:
    # %{
    #   "killmail_id" => 123456789,
    #   "zkb" => %{
    #     "locationID" => 30000142,
    #     "hash" => "hash_string",
    #     "fittedValue" => 1000000,
    #     "totalValue" => 1200000,
    #     "points" => 1,
    #     "npc" => false,
    #     ...
    #   }
    # }

    # Extract the killmail_id and hash
    kill_id = Map.get(zkill_data, "killmail_id")
    hash = get_in(zkill_data, ["zkb", "hash"])

    if kill_id && hash do
      case ESIService.get_killmail(kill_id, hash) do
        {:ok, esi_data} ->
          # Create a complete kill structure with both ESI and ZKill data
          Map.merge(zkill_data, %{"esi_killmail" => esi_data})

        error ->
          AppLogger.processor_error(
            "[StructuredFormatter] Failed to get ESI data for killmail #{kill_id}: #{inspect(error)}"
          )

          # Return original zkill data
          zkill_data
      end
    else
      AppLogger.processor_warn(
        "[StructuredFormatter] Missing killmail_id or hash in zkill data: #{inspect(zkill_data)}"
      )

      zkill_data
    end
  end

  # Format kills list for system notification
  defp format_system_kills(kills) do
    Enum.map_join(kills, "\n", fn kill ->
      # Get kill ID and value from zkill data
      kill_id = Map.get(kill, "killmail_id")
      total_value = get_in(kill, ["zkb", "totalValue"]) || 0

      # Try to get victim and ship info from ESI data if available
      esi_data = Map.get(kill, "esi_killmail", %{})

      # Extract victim info from ESI data if available
      victim_data = Map.get(esi_data, "victim", %{})
      victim_id = Map.get(victim_data, "character_id")
      ship_type_id = Map.get(victim_data, "ship_type_id")

      # Use ESI names when available or fallback to defaults
      {victim_name, ship_name} = get_victim_and_ship_names(victim_id, ship_type_id)

      # Format the kill details
      formatted_value = format_compact_isk_value(total_value)

      # Return the formatted kill line
      "[#{victim_name} (#{ship_name})](https://zkillboard.com/kill/#{kill_id}/) - #{formatted_value}"
    end)
  end

  # Get victim and ship names using ESI API
  defp get_victim_and_ship_names(victim_id, ship_type_id) do
    # Get character name
    victim_name =
      if victim_id do
        case ESIService.get_character_info(victim_id) do
          {:ok, char_info} -> Map.get(char_info, "name", "Unknown")
          _ -> "Unknown"
        end
      else
        "Unknown"
      end

    # Get ship name
    ship_name =
      if ship_type_id do
        case ESIService.get_ship_type_name(ship_type_id) do
          {:ok, ship_info} -> Map.get(ship_info, "name", "Unknown Ship")
          _ -> "Unknown Ship"
        end
      else
        "Unknown Ship"
      end

    {victim_name, ship_name}
  end

  # Format ISK value in a compact way
  defp format_compact_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B ISK"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M ISK"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K ISK"
      true -> "#{Float.round(value, 1)} ISK"
    end
  end

  defp format_compact_isk_value(_), do: "Unknown Value"

  # Add shattered field if applicable
  defp add_shattered_field(fields, true, true) do
    fields ++ [%{name: "Shattered", value: "Yes", inline: true}]
  end

  defp add_shattered_field(fields, _, _), do: fields

  # Add statics field if applicable
  defp add_statics_field(fields, true, formatted_statics)
       when formatted_statics != nil and formatted_statics != "None" do
    fields ++ [%{name: "Statics", value: formatted_statics, inline: true}]
  end

  defp add_statics_field(fields, _, _), do: fields

  # Add region field if available
  defp add_region_field(fields, nil), do: fields

  defp add_region_field(fields, region_name) do
    encoded_region_name = URI.encode(region_name)
    region_link = "[#{region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"
    fields ++ [%{name: "Region", value: region_link, inline: true}]
  end

  # Add effect field if available for wormhole systems
  defp add_effect_field(fields, true, effect_name)
       when effect_name != nil and effect_name != "" do
    fields ++ [%{name: "Effect", value: effect_name, inline: true}]
  end

  defp add_effect_field(fields, _, _), do: fields

  # Helper to determine system icon URL based on MapSystem data
  defp determine_system_icon(is_wormhole, type_description, sun_type_id) do
    # Parse sun_type_id if it's a string
    sun_id = parse_sun_type_id(sun_type_id)

    # First check if we have a valid sun_type_id
    if sun_id && sun_id > 0 do
      # Use the actual sun type for the icon (more accurate representation)
      AppLogger.processor_info("[StructuredFormatter] Using sun type icon for system: #{sun_id}")
      "https://images.evetech.net/types/#{sun_id}/icon"
    else
      # Fallback to category-based icons
      get_system_type_icon(is_wormhole, type_description)
    end
  end

  # Helper to get the appropriate icon based on system type
  defp get_system_type_icon(is_wormhole, type_description) do
    cond do
      is_wormhole -> @wormhole_icon
      type_description && String.contains?(type_description, "High-sec") -> @highsec_icon
      type_description && String.contains?(type_description, "Low-sec") -> @lowsec_icon
      type_description && String.contains?(type_description, "Null-sec") -> @nullsec_icon
      true -> @default_icon
    end
  end

  # Helper to parse sun_type_id values which might be strings
  defp parse_sun_type_id(nil), do: nil
  defp parse_sun_type_id(id) when is_integer(id), do: id

  defp parse_sun_type_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp parse_sun_type_id(_), do: nil

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
    AppLogger.processor_debug("[StructuredFormatter.format_statics_list] Nil statics list")
    "None"
  end

  defp format_statics_list([]) do
    AppLogger.processor_debug("[StructuredFormatter.format_statics_list] Empty statics list")
    "None"
  end

  defp format_statics_list(statics) when is_list(statics) do
    formatted =
      Enum.map(statics, fn static ->
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
      has_destination_info?(static) -> format_static_with_destination(static)
      has_name_info?(static) -> get_static_name(static)
      is_binary(static) -> static
      true -> log_unrecognized_static(static)
    end
  end

  defp format_single_static(static) when is_binary(static) do
    static
  end

  defp format_single_static(static) do
    log_unrecognized_static(static)
  end

  # Helper function to check if static has destination info
  defp has_destination_info?(static) do
    Map.has_key?(static, "destination") || Map.has_key?(static, :destination)
  end

  # Helper function to check if static has name info
  defp has_name_info?(static) do
    Map.has_key?(static, "name") || Map.has_key?(static, :name)
  end

  # Helper function to get static name
  defp get_static_name(static) do
    Map.get(static, "name") || Map.get(static, :name)
  end

  # Helper function to format static with destination info
  defp format_static_with_destination(static) do
    name = get_static_name(static)
    destination = Map.get(static, "destination") || Map.get(static, :destination)
    dest_short = get_in(destination, ["short_name"]) || get_in(destination, [:short_name])

    if name && dest_short do
      "#{name} (#{dest_short})"
    else
      name
    end
  end

  # Helper function to log unrecognized static format
  defp log_unrecognized_static(static) do
    AppLogger.processor_warn(
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

  # Get application version from Version module
  defp get_app_version do
    # Use our new Version module which reads the version from mix.exs at compile time
    # This eliminates the need for environment variables for versioning
    WandererNotifier.Config.Version.version()
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
    AppLogger.processor_info("[StructuredFormatter] Creating status message with title: #{title}")

    # Prepare all the data needed for the status message
    uptime_str = format_uptime(uptime)
    license_icon = get_license_icon(license_status)
    websocket_icon = get_websocket_status_icon(stats)
    notification_info = get_notification_info(stats)
    formatted_features = format_feature_statuses(features_status)

    # Prepare fields data as a map to reduce parameter count
    notification_data = %{
      title: title,
      description: description,
      uptime_str: uptime_str,
      license_icon: license_icon,
      websocket_icon: websocket_icon,
      systems_count: systems_count,
      characters_count: characters_count,
      notification_info: notification_info,
      formatted_features: formatted_features
    }

    # Build the response structure
    build_status_notification(notification_data)
  end

  # Format uptime for display
  defp format_uptime(nil), do: "🚀 Just started"

  defp format_uptime(uptime) do
    days = div(uptime, 86_400)
    hours = div(rem(uptime, 86_400), 3600)
    minutes = div(rem(uptime, 3600), 60)
    seconds = rem(uptime, 60)
    "⏱️ #{days}d #{hours}h #{minutes}m #{seconds}s"
  end

  # Get license icon based on validity and premium status
  defp get_license_icon(license_status) do
    # Since premium tier is removed, we only check for license validity
    if license_status.valid do
      "✅"
    else
      "❌"
    end
  end

  # Get notification info string
  defp get_notification_info(stats) do
    if Map.has_key?(stats, :notifications) do
      format_notification_counts(stats.notifications)
    else
      "No notifications sent yet"
    end
  end

  # Extract and format feature statuses
  defp format_feature_statuses(features_status) do
    # Extract primary feature statuses
    primary_features = %{
      kill_notifications: Map.get(features_status, :kill_notifications_enabled, true),
      tracked_systems_notifications: Map.get(features_status, :system_tracking_enabled, true),
      tracked_characters_notifications:
        Map.get(features_status, :character_tracking_enabled, true),
      activity_charts: Map.get(features_status, :activity_charts, false)
    }

    # For debugging display
    AppLogger.processor_debug(
      "[StructuredFormatter] Found feature statuses: #{inspect(features_status)}"
    )

    AppLogger.processor_debug(
      "[StructuredFormatter] Extracted primary features: #{inspect(primary_features)}"
    )

    # Format primary feature statuses
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
  end

  # Build the final status notification structure
  defp build_status_notification(data) do
    %{
      type: :status_notification,
      title: data.title,
      description: "#{data.description}\n\n**System Status Overview:**",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        # Use the EVE Online logo or similar icon
        url: "https://images.evetech.net/corporations/1_000_001/logo?size=128"
      },
      footer: %{
        text: "Wanderer Notifier v#{get_app_version()}"
      },
      fields: [
        %{name: "Uptime", value: data.uptime_str, inline: true},
        %{name: "License", value: data.license_icon, inline: true},
        %{name: "WebSocket", value: data.websocket_icon, inline: true},
        %{name: "Systems", value: "🗺️ #{data.systems_count}", inline: true},
        %{name: "Characters", value: "👤 #{data.characters_count}", inline: true},
        %{name: "📊 Notifications", value: data.notification_info, inline: false},
        %{name: "⚙️ Primary Features", value: data.formatted_features, inline: false}
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

  # Helper to get websocket status icon based on connection state and last message time
  defp get_websocket_status_icon(stats) do
    if Map.has_key?(stats, :websocket) do
      ws_status = stats.websocket
      get_icon_by_connection_state(ws_status)
    else
      "❓"
    end
  end

  defp get_icon_by_connection_state(%{connected: false}), do: "🔴"

  defp get_icon_by_connection_state(%{connected: true, last_message: nil}), do: "🟡"

  defp get_icon_by_connection_state(%{connected: true, last_message: last_message}) do
    time_diff = DateTime.diff(DateTime.utc_now(), last_message, :second)

    cond do
      time_diff < 60 -> "🟢"
      time_diff < 300 -> "🟡"
      true -> "🟠"
    end
  end

  @doc """
  Converts a generic notification structure to Discord's specific format.
  This is the interface between our internal notification format and Discord's requirements.

  ## Parameters
    - notification: The generic notification structure

  ## Returns
    - A map in Discord's expected format
  """
  def to_discord_format(notification) do
    # Extract components if available
    components = Map.get(notification, :components, [])

    # Convert to Discord embed format
    %{
      "title" => notification.title,
      "description" => notification.description,
      "color" => notification.color,
      "url" => Map.get(notification, :url),
      "timestamp" => Map.get(notification, :timestamp),
      "footer" => Map.get(notification, :footer),
      "thumbnail" => Map.get(notification, :thumbnail),
      "image" => Map.get(notification, :image),
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
    |> add_components_if_present(components)
  end

  # Helper to add components if present
  defp add_components_if_present(embed, []), do: embed
  defp add_components_if_present(embed, components), do: Map.put(embed, "components", components)
end
