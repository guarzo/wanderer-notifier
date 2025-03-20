defmodule WandererNotifier.Notifiers.Formatter do
  @moduledoc """
  Notification formatting utilities for Discord notifications.

  This module provides standardized formatting for various notification types,
  making it easier to maintain consistent notification styles for Discord.
  It handles common formatting tasks and data transformations needed for rich notifications.
  """

  require Logger

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

  # For backward compatibility with code that might still use platform parameter
  def convert_color(:discord, color), do: convert_color(color)

  @doc """
  Creates a standard formatted kill notification embed/attachment.
  Returns data in a generic format that can be converted to platform-specific format.

  ## Parameters
    - enriched_kill: The enriched killmail data
    - kill_id: The killmail ID

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_kill_notification(enriched_kill, kill_id) do
    # Extract common data
    victim = Map.get(enriched_kill, "victim") || %{}
    victim_name = get_value(victim, ["character_name"], "Unknown Pilot")
    victim_ship = get_value(victim, ["ship_type_name"], "Unknown Ship")
    victim_corp = get_value(victim, ["corporation_name"], "Unknown Corp")
    victim_alliance = get_value(victim, ["alliance_name"], nil)
    victim_ship_type_id = get_value(victim, ["ship_type_id"], nil)
    victim_character_id = get_value(victim, ["character_id"], nil)

    # Extract zkillboard data
    zkb = Map.get(enriched_kill, "zkb") || %{}
    kill_value = Map.get(zkb, "totalValue", 0)
    formatted_value = format_isk_value(kill_value)

    # Kill time and system info
    kill_time = Map.get(enriched_kill, "killmail_time")
    system_name = Map.get(enriched_kill, "solar_system_name") || "Unknown System"

    # Attackers information
    attackers = Map.get(enriched_kill, "attackers") || []
    attackers_count = length(attackers)

    # Final blow details
    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        Map.get(attacker, "final_blow") in [true, "true"]
      end)

    is_npc_kill = Map.get(zkb, "npc") == true

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
  Creates a standard formatted new tracked character notification.

  ## Parameters
    - character: The character data to create a notification for

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_character_notification(character) do
    # Extract all character information
    character_id = extract_character_id(character)
    character_name = extract_character_name(character)
    corporation_name = extract_corporation_name(character)
    corporation_id = extract_corporation_id(character)

    # Log all extracted values for debugging
    Logger.info(
      "[Formatter] Character notification - id: #{character_id}, name: #{character_name}, " <>
        "corporation_name: #{corporation_name}, corporation_id: #{inspect(corporation_id)}"
    )

    Logger.info("[Formatter] Character data: #{inspect(character, pretty: true, limit: 1000)}")

    %{
      type: :character_notification,
      title: "New Character Tracked",
      description: "A new character has been added to the tracking list.",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        url: "https://imageserver.eveonline.com/Character/#{character_id}_128.jpg"
      },
      fields:
        [
          %{
            name: "Character",
            value: "[#{character_name}](https://zkillboard.com/character/#{character_id}/)",
            inline: true
          }
        ] ++
          if corporation_name do
            # Create a link to zKillboard if we have the corporation ID, otherwise just use the name
            corp_value =
              if corporation_id do
                "[#{corporation_name}](https://zkillboard.com/corporation/#{corporation_id}/)"
              else
                corporation_name
              end

            [%{name: "Corporation", value: corp_value, inline: true}]
          else
            []
          end
    }
  end

  @doc """
  Creates a standard formatted system notification.

  ## Parameters
    - system: The system data to create a notification for

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_system_notification(system) do
    # Extract all system information with normalized data
    require Logger

    Logger.debug(
      "[Formatter] Processing system notification with original data: #{inspect(system, pretty: true, limit: 2000)}"
    )

    system = normalize_system_data(system)

    Logger.debug(
      "[Formatter] Using normalized system data: #{inspect(system, pretty: true, limit: 2000)}"
    )

    # Extract essential system information using consistent extraction methods
    system_id = extract_system_id(system)
    system_name = extract_system_name(system)
    type_description = extract_type_description(system)

    Logger.info(
      "[Formatter] System ID: #{system_id}, System Name: #{system_name}, Type Description: #{type_description}"
    )

    if is_nil(type_description) do
      Logger.error(
        "[Formatter] Cannot format system notification: type_description not available for system #{system_name} (ID: #{system_id})"
      )

      nil
    else
      # Extract additional system information
      effect_name = extract_effect_name(system)
      is_shattered = extract_is_shattered(system)
      statics = extract_statics(system)
      static_details = extract_static_details(system)
      region_name = extract_region_name(system)
      sun_type_id = extract_sun_type_id(system)

      # Determine system properties
      is_wormhole =
        String.contains?(type_description || "", "Class") ||
          (extract_class_title(system) != nil &&
             (String.contains?(extract_class_title(system), "C") ||
                String.contains?(extract_class_title(system), "Class")))

      # Generate notification components
      title = generate_system_title(type_description, extract_class_title(system), is_wormhole)

      description =
        generate_system_description(type_description, extract_class_title(system), is_wormhole)

      icon_url = determine_system_icon(sun_type_id, effect_name, type_description)
      embed_color = determine_system_color(type_description, is_wormhole)
      display_name = format_system_display_name(system_id, system_name)

      # Build fields list
      fields = [%{name: "System", value: display_name, inline: true}]

      # Add shattered field if applicable
      fields =
        if is_wormhole && is_shattered do
          fields ++ [%{name: "Shattered", value: "Yes", inline: true}]
        else
          fields
        end

      # Add statics field if applicable for wormhole systems
      fields =
        if is_wormhole do
          add_statics_field(fields, statics, static_details, system_name)
        else
          fields
        end

      # Add region field if available
      fields =
        if region_name do
          encoded_region_name = URI.encode(region_name)

          region_link =
            "[#{region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"

          fields ++ [%{name: "Region", value: region_link, inline: true}]
        else
          fields
        end

      # Create the generic notification structure
      %{
        type: :system_notification,
        title: title,
        description: description,
        color: embed_color,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        thumbnail: %{url: icon_url},
        fields: fields
      }
    end
  end

  # Extract system ID with consistent precedence
  defp extract_system_id(system) when is_map(system) do
    require Logger

    system_id =
      Map.get(system, "solar_system_id") ||
        Map.get(system, "system_id") ||
        Map.get(system, "id") ||
        Map.get(system, "systemId")

    Logger.debug("[Formatter] Extracted system_id: #{inspect(system_id)}")
    system_id
  end

  # Extract system name with consistent precedence
  defp extract_system_name(system) when is_map(system) do
    require Logger

    # Get system name components
    orig_name = get_original_name(system)
    temp_name = get_temporary_name(system)
    basic_name = get_basic_name(system)

    system_name =
      cond do
        # If both temporary and original names exist, combine them
        temp_name && temp_name != "" && orig_name && orig_name != "" ->
          formatted_name = "#{temp_name} (#{orig_name})"

          Logger.debug(
            "[Formatter] Using combined temporary_name and original_name: #{formatted_name}"
          )

          formatted_name

        # If only original name exists, use it
        orig_name && orig_name != "" ->
          Logger.debug("[Formatter] Using just original_name: #{orig_name}")
          orig_name

        # Fall back to basic name
        true ->
          Logger.debug("[Formatter] Falling back to basic_name: #{basic_name}")
          basic_name
      end

    system_name
  end

  # Get original name from system data
  defp get_original_name(system) do
    get_in(system, ["system", "original_name"]) ||
      Map.get(system, "original_name")
  end

  # Get temporary name from system data
  defp get_temporary_name(system) do
    get_in(system, ["system", "temporary_name"]) ||
      Map.get(system, "temporary_name")
  end

  # Get basic name from system data
  defp get_basic_name(system) do
    get_in(system, ["system", "name"]) ||
      Map.get(system, "display_name") ||
      Map.get(system, "solar_system_name") ||
      Map.get(system, "system_name") ||
      Map.get(system, "name") ||
      "Unknown System"
  end

  # Extract type description with consistent precedence
  defp extract_type_description(system) when is_map(system) do
    require Logger

    type_description =
      Map.get(system, "type_description") ||
        get_in(system, ["staticInfo", "typeDescription"]) ||
        Map.get(system, "typeDescription")

    Logger.debug("[Formatter] Extracted type_description: #{inspect(type_description)}")
    type_description
  end

  # Extract class title with consistent precedence
  defp extract_class_title(system) when is_map(system) do
    require Logger

    class_title =
      get_in(system, ["system", "class_title"]) ||
        Map.get(system, "class_title") ||
        get_in(system, ["staticInfo", "class_title"])

    Logger.debug("[Formatter] Extracted class_title: #{inspect(class_title)}")
    class_title
  end

  # Extract effect name with consistent precedence
  defp extract_effect_name(system) when is_map(system) do
    require Logger

    effect_name =
      Map.get(system, "effect_name") ||
        get_in(system, ["staticInfo", "effectName"])

    Logger.debug("[Formatter] Extracted effect_name: #{inspect(effect_name)}")
    effect_name
  end

  # Extract is_shattered with consistent precedence
  defp extract_is_shattered(system) when is_map(system) do
    require Logger

    is_shattered =
      Map.get(system, "is_shattered") ||
        get_in(system, ["staticInfo", "isShattered"])

    Logger.debug("[Formatter] Extracted is_shattered: #{inspect(is_shattered)}")
    is_shattered
  end

  # Extract statics with consistent precedence
  defp extract_statics(system) when is_map(system) do
    require Logger

    statics =
      Map.get(system, "statics") ||
        get_in(system, ["staticInfo", "statics"]) ||
        []

    Logger.debug("[Formatter] Extracted statics: #{inspect(statics)}")
    statics
  end

  # Extract static_details with consistent precedence
  defp extract_static_details(system) when is_map(system) do
    require Logger

    static_details =
      Map.get(system, "static_details") ||
        get_in(system, ["staticInfo", "static_details"])

    Logger.debug("[Formatter] Extracted static_details: #{inspect(static_details)}")
    static_details
  end

  # Extract region_name with consistent precedence
  defp extract_region_name(system) when is_map(system) do
    require Logger

    region_name =
      Map.get(system, "region_name") ||
        get_in(system, ["staticInfo", "regionName"])

    Logger.debug("[Formatter] Extracted region_name: #{inspect(region_name)}")
    region_name
  end

  # Extract sun_type_id with consistent precedence
  defp extract_sun_type_id(system) when is_map(system) do
    require Logger

    sun_type_id =
      Map.get(system, "sun_type_id") ||
        get_in(system, ["staticInfo", "sunTypeId"])

    Logger.debug("[Formatter] Extracted sun_type_id: #{inspect(sun_type_id)}")
    sun_type_id
  end

  # Generate system title
  defp generate_system_title(type_description, class_title, is_wormhole) do
    if is_wormhole && class_title do
      "New #{class_title} System Mapped"
    else
      "New #{type_description} System Mapped"
    end
  end

  # Generate system description
  defp generate_system_description(type_description, class_title, is_wormhole) do
    if is_wormhole && class_title do
      "A #{class_title} wormhole system has been discovered and added to the map."
    else
      "A #{type_description} system has been discovered and added to the map."
    end
  end

  # Format system display name for zkill link
  defp format_system_display_name(system_id, system_name) do
    if is_binary(system_id) && String.contains?(system_id, "-") do
      # For UUID-style IDs, just show the name without a link
      system_name
    else
      "[#{system_name}](https://zkillboard.com/system/#{system_id}/)"
    end
  end

  # Add statics field to embed fields
  defp add_statics_field(fields, statics, static_details, system_name) do
    require Logger

    # First try to use static_details which has destination information
    if is_list(static_details) && length(static_details) > 0 do
      statics_str = format_statics_list(static_details)
      Logger.debug("[Formatter] Adding statics with destination details: #{statics_str}")
      fields ++ [%{name: "Statics", value: statics_str, inline: true}]
    else
      # Fall back to basic statics list if detailed info is not available
      if is_list(statics) && length(statics) > 0 do
        statics_str = format_statics_list(statics)
        Logger.debug("[Formatter] Adding statics to system notification: #{statics_str}")
        fields ++ [%{name: "Statics", value: statics_str, inline: true}]
      else
        Logger.warning(
          "[Formatter] Wormhole system without statics: #{system_name}, tried statics=#{inspect(statics)}"
        )

        fields
      end
    end
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
    # This is mostly a direct mapping since our generic format is close to Discord's
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
    require Logger

    if final_blow_attacker do
      # Extract attacker details with proper logging
      Logger.debug(
        "[Formatter] Extracting final blow details from attacker: #{inspect(final_blow_attacker, pretty: true, limit: 300)}"
      )

      # Extract character_id using consistent approach
      final_blow_character_id =
        cond do
          # Direct character_id field
          Map.has_key?(final_blow_attacker, "character_id") ->
            Logger.debug("[Formatter] Found final blow character_id field")
            final_blow_attacker["character_id"]

          # Character struct with eve_id
          Map.has_key?(final_blow_attacker, :__struct__) &&
              final_blow_attacker.__struct__ == WandererNotifier.Data.Character ->
            Logger.debug("[Formatter] Found Character struct for final blow")
            final_blow_attacker.eve_id

          # Nested character object
          is_map(final_blow_attacker["character"]) &&
              Map.has_key?(final_blow_attacker["character"], "eve_id") ->
            Logger.debug("[Formatter] Found nested character with eve_id for final blow")
            final_blow_attacker["character"]["eve_id"]

          # Check for atom key :character_id
          Map.has_key?(final_blow_attacker, :character_id) ->
            Logger.debug("[Formatter] Found atom key :character_id for final blow")
            final_blow_attacker.character_id

          true ->
            Logger.warning("[Formatter] Could not find character_id for final blow attacker")
            nil
        end

      # Extract character name
      final_blow_name =
        if is_npc_kill do
          Logger.debug("[Formatter] Using NPC as final blow attacker name")
          "NPC"
        else
          name = Map.get(final_blow_attacker, "character_name")
          Logger.debug("[Formatter] Found final blow character name: #{inspect(name)}")
          name || "Unknown Pilot"
        end

      # Extract ship type
      final_blow_ship = Map.get(final_blow_attacker, "ship_type_name") || "Unknown Ship"
      Logger.debug("[Formatter] Found final blow ship type: #{inspect(final_blow_ship)}")

      Logger.debug("[Formatter] Final blow character ID: #{inspect(final_blow_character_id)}")

      # Create response with appropriate formatting
      if final_blow_character_id && !is_npc_kill do
        # If we have a character ID and it's not an NPC kill, include a zkillboard link
        Logger.debug("[Formatter] Creating final blow details with zkillboard link")

        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: final_blow_character_id,
          text:
            "[#{final_blow_name}](https://zkillboard.com/character/#{final_blow_character_id}/) (#{final_blow_ship})"
        }
      else
        # Otherwise just format the name and ship without a link
        Logger.debug("[Formatter] Creating final blow details without link")

        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: nil,
          text: "#{final_blow_name} (#{final_blow_ship})"
        }
      end
    else
      # No final blow attacker found, return default values
      Logger.debug("[Formatter] No final blow attacker found, using defaults")

      %{
        name: "Unknown Pilot",
        ship: "Unknown Ship",
        character_id: nil,
        text: "Unknown Pilot (Unknown Ship)"
      }
    end
  end

  # Helper to determine system icon URL based on type
  defp determine_system_icon(sun_type_id, effect_name, type_description) do
    if sun_type_id do
      "https://images.evetech.net/types/#{sun_type_id}/icon"
    else
      cond do
        effect_name == "Pulsar" ->
          "https://images.evetech.net/types/30488/icon"

        effect_name == "Magnetar" ->
          "https://images.evetech.net/types/30484/icon"

        effect_name == "Wolf-Rayet Star" ->
          "https://images.evetech.net/types/30489/icon"

        effect_name == "Black Hole" ->
          "https://images.evetech.net/types/30483/icon"

        effect_name == "Cataclysmic Variable" ->
          "https://images.evetech.net/types/30486/icon"

        effect_name == "Red Giant" ->
          "https://images.evetech.net/types/30485/icon"

        String.contains?(type_description, "High-sec") ->
          "https://images.evetech.net/types/45041/icon"

        String.contains?(type_description, "Low-sec") ->
          "https://images.evetech.net/types/45031/icon"

        String.contains?(type_description, "Null-sec") ->
          "https://images.evetech.net/types/45033/icon"

        true ->
          "https://images.evetech.net/types/3802/icon"
      end
    end
  end

  # Helper to determine system color based on type
  defp determine_system_color(type_description, is_wormhole) do
    cond do
      String.contains?(type_description, "High-sec") ->
        @highsec_color

      String.contains?(type_description, "Low-sec") ->
        @lowsec_color

      String.contains?(type_description, "Null-sec") ->
        @nullsec_color

      is_wormhole ||
        String.contains?(type_description, "Class") ||
          String.contains?(type_description, "Wormhole") ->
        @wormhole_color

      true ->
        @default_color
    end
  end

  # Helper to format a list of statics with improved handling for different data formats
  defp format_statics_list(statics) do
    require Logger

    # If statics is already a formatted string, just return it
    if is_binary(statics) do
      Logger.debug("[Formatter] Statics is already a string: #{statics}")
      statics
    else
      # Safely handle nil case
      statics_list = if is_nil(statics), do: [], else: statics
      Logger.debug("[Formatter] Processing statics list with #{length(statics_list)} items")

      # Map each static and join with comma
      formatted = Enum.map(statics_list, fn static -> format_single_static(static) end)
      Enum.join(formatted, ", ")
    end
  end

  # Format a single static wormhole entry
  defp format_single_static(static) do
    require Logger

    cond do
      # Handle map with destination information (complete format)
      is_map(static) && Map.has_key?(static, "destination") ->
        name = Map.get(static, "name")
        destination = Map.get(static, "destination") || %{}
        short_name = Map.get(destination, "short_name")

        if name && short_name do
          formatted = "#{name} (#{short_name})"
          Logger.debug("[Formatter] Formatted static with destination info: #{formatted}")
          formatted
        else
          Logger.debug("[Formatter] Static has name but no short_name: #{inspect(name)}")
          name || "Unknown"
        end

      # Handle map with name key (common format)
      is_map(static) && Map.has_key?(static, "name") ->
        name = Map.get(static, "name")
        Logger.debug("[Formatter] Using static name: #{inspect(name)}")
        name

      # Handle simple string static
      is_binary(static) ->
        Logger.debug("[Formatter] Static is already a string: #{static}")
        static

      # Fallback for any other format
      true ->
        formatted = inspect(static)
        Logger.debug("[Formatter] Using fallback format for static: #{formatted}")
        formatted
    end
  end

  # Helper to normalize system data by merging nested data if present
  defp normalize_system_data(system) do
    require Logger

    Logger.debug(
      "[Formatter] Normalizing system data: #{inspect(system, pretty: true, limit: 5000)}"
    )

    # First merge data if it exists
    system =
      if Map.has_key?(system, "data") and is_map(system["data"]) do
        Map.merge(system, system["data"])
      else
        system
      end

    # Handle staticInfo data structure common in the API
    system =
      if Map.has_key?(system, "staticInfo") and is_map(system["staticInfo"]) do
        static_info = system["staticInfo"]

        # Extract key information from staticInfo
        system =
          if Map.has_key?(static_info, "typeDescription") do
            Map.put(system, "type_description", static_info["typeDescription"])
          else
            system
          end

        # Extract statics if they exist
        system =
          if Map.has_key?(static_info, "statics") do
            statics = static_info["statics"]

            # Check if statics is empty but we know it's a wormhole - apply default statics
            statics =
              if is_list(statics) && statics == [] do
                # Get system ID to look up default statics
                _system_id =
                  Map.get(system, "solar_system_id") ||
                    Map.get(system, :solar_system_id) ||
                    Map.get(system, "system_id") ||
                    Map.get(system, :system_id) ||
                    Map.get(system, "systemId") ||
                    Map.get(system, :systemId)

                # No default statics - we'll use what we have
                statics
              else
                statics
              end

            Map.put(system, "statics", statics)
          else
            system
          end

        # Copy over system name and ID if available in the parent object
        system =
          if Map.get(system, "systemName") && !Map.has_key?(system, "system_name") do
            Map.put(system, "system_name", system["systemName"])
          else
            system
          end

        system =
          if Map.get(system, "systemId") && !Map.has_key?(system, "system_id") do
            Map.put(system, "system_id", system["systemId"])
          else
            system
          end

        # Add effect name and class if not already present
        system =
          if Map.has_key?(static_info, "effectName") && !Map.has_key?(system, "effect_name") do
            Map.put(system, "effect_name", static_info["effectName"])
          else
            system
          end

        system =
          if Map.has_key?(static_info, "isShattered") && !Map.has_key?(system, "is_shattered") do
            Map.put(system, "is_shattered", static_info["isShattered"])
          else
            system
          end

        system
      else
        system
      end

    # Also check for static info at the top level since some API formats include it there
    system =
      if Map.has_key?(system, "statics") && !is_list(system["statics"]) do
        # Convert non-list statics to list format
        Map.put(system, "statics", [system["statics"]])
      else
        system
      end

    # Check if we need to extract temporary_name for display
    system =
      if Map.has_key?(system, "temporary_name") && !Map.has_key?(system, "display_name") do
        # If we have a temporary_name and original_name, combine them for display
        if Map.has_key?(system, "original_name") do
          Map.put(
            system,
            "display_name",
            "#{system["temporary_name"]} (#{system["original_name"]})"
          )
        else
          Map.put(system, "display_name", system["temporary_name"])
        end
      else
        system
      end

    Logger.debug(
      "[Formatter] Normalized system data: #{inspect(system, pretty: true, limit: 5000)}"
    )

    system
  end

  # Retrieves a value from a map checking both string and atom keys.
  # Tries each key in the provided list until a value is found.
  defp get_value(map, keys, default) do
    Enum.find_value(keys, default, fn key ->
      Map.get(map, key) || Map.get(map, String.to_atom(key))
    end)
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

  # Character data extraction functions

  @doc """
  Extracts a character ID from a character map following the API format.

  According to the API documentation, characters are returned with:
  1. A nested 'character' object containing 'eve_id' field (standard format)
  2. Direct 'character_id' field for notification format

  Returns the ID as a string, or nil if not found.
  """
  def extract_character_id(character) when is_map(character) do
    require Logger

    # Log the input for debugging
    Logger.debug(
      "[Formatter] Extracting character_id from: #{inspect(character, pretty: true, limit: 300)}"
    )

    character_id =
      cond do
        # Handle Character struct
        Map.has_key?(character, :__struct__) &&
            character.__struct__ == WandererNotifier.Data.Character ->
          Logger.debug("[Formatter] Found character_id in Character struct (eve_id)")
          character.eve_id

        # Standard API format with nested character object
        is_map(character["character"]) && Map.has_key?(character["character"], "eve_id") ->
          Logger.debug("[Formatter] Found character_id in standard API format (character.eve_id)")
          character["character"]["eve_id"]

        # Direct character_id (notification format)
        Map.has_key?(character, "character_id") ->
          Logger.debug("[Formatter] Found character_id in notification format (character_id)")
          character["character_id"]

        # Check for atom key :eve_id
        Map.has_key?(character, :eve_id) ->
          Logger.debug("[Formatter] Found character_id as atom key (:eve_id)")
          character.eve_id

        true ->
          Logger.warning("[Formatter] Could not find character_id in any supported format")
          nil
      end

    # Convert to string if needed for consistency
    case character_id do
      id when is_integer(id) ->
        Logger.debug("[Formatter] Converting integer character_id to string: #{id}")
        Integer.to_string(id)

      id when is_binary(id) ->
        id

      _ ->
        nil
    end
  end

  @doc """
  Extracts a character name from a character map following the API format.

  According to the API documentation, characters are returned with:
  1. A nested 'character' object containing 'name' field (standard format)
  2. Direct 'character_name' field for notification format

  Returns the name as a string, or a default value if not found.
  """
  def extract_character_name(character, default \\ "Unknown Character") when is_map(character) do
    require Logger

    # Log the input for debugging
    Logger.debug(
      "[Formatter] Extracting character_name from: #{inspect(character, pretty: true, limit: 300)}"
    )

    character_name =
      cond do
        # Handle Character struct
        Map.has_key?(character, :__struct__) &&
            character.__struct__ == WandererNotifier.Data.Character ->
          Logger.debug("[Formatter] Found character_name in Character struct (name)")
          character.name

        # Standard API format with nested character object
        is_map(character["character"]) && Map.has_key?(character["character"], "name") ->
          Logger.debug("[Formatter] Found character_name in standard API format (character.name)")
          character["character"]["name"]

        # Direct character_name (notification format)
        Map.has_key?(character, "character_name") ->
          Logger.debug("[Formatter] Found character_name in notification format (character_name)")
          character["character_name"]

        # Check for atom key :name
        Map.has_key?(character, :name) ->
          Logger.debug("[Formatter] Found character_name as atom key (:name)")
          character.name

        true ->
          Logger.warning("[Formatter] Could not find character_name in any supported format")
          nil
      end

    if is_nil(character_name) || character_name == "" do
      Logger.debug("[Formatter] Using default character name: #{default}")
      default
    else
      character_name
    end
  end

  @doc """
  Extracts a corporation ID from a character map following the API format.

  According to the API documentation, characters are returned with:
  1. A nested 'character' object containing 'corporation_id' field (standard format)
  2. Direct 'corporation_id' field for notification format

  Returns the ID as an integer, or nil if not found.
  """
  def extract_corporation_id(character) when is_map(character) do
    require Logger

    # Log the input for debugging
    Logger.debug(
      "[Formatter] Extracting corporation_id from: #{inspect(character, pretty: true, limit: 300)}"
    )

    corporation_id =
      cond do
        # Handle Character struct
        Map.has_key?(character, :__struct__) &&
            character.__struct__ == WandererNotifier.Data.Character ->
          Logger.debug("[Formatter] Found corporation_id in Character struct (corporation_id)")
          character.corporation_id

        # Standard API format with nested character object
        is_map(character["character"]) && Map.has_key?(character["character"], "corporation_id") ->
          Logger.debug(
            "[Formatter] Found corporation_id in standard API format (character.corporation_id)"
          )

          character["character"]["corporation_id"]

        # Direct corporation_id (notification format)
        Map.has_key?(character, "corporation_id") ->
          Logger.debug("[Formatter] Found corporation_id in notification format (corporation_id)")
          character["corporation_id"]

        # Check for atom key :corporation_id
        Map.has_key?(character, :corporation_id) ->
          Logger.debug("[Formatter] Found corporation_id as atom key (:corporation_id)")
          character.corporation_id

        true ->
          Logger.warning("[Formatter] Could not find corporation_id in any supported format")
          nil
      end

    # Convert to integer if a string
    case corporation_id do
      id when is_integer(id) ->
        Logger.debug("[Formatter] Corporation ID is already an integer: #{id}")
        id

      id when is_binary(id) ->
        Logger.debug("[Formatter] Converting string corporation_id to integer: #{id}")

        case Integer.parse(id) do
          {int_id, ""} ->
            int_id

          _ ->
            Logger.warning("[Formatter] Failed to parse corporation_id as integer: #{id}")
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Extracts a corporation name from a character map following the API format.

  According to the API documentation, characters are returned with:
  1. A nested 'character' object containing 'corporation_ticker' field (standard format)
  2. Direct 'corporation_ticker' field for notification format

  Returns the name as a string, or a default value if not found.
  If no corporation name is found but corporation_id is available, attempts to look it up from ESI.
  """
  def extract_corporation_name(character, default \\ "Unknown Corporation")
      when is_map(character) do
    require Logger

    # Log the input for debugging
    Logger.debug(
      "[Formatter] Extracting corporation_name from: #{inspect(character, pretty: true, limit: 300)}"
    )

    corporation_name =
      cond do
        # Handle Character struct with corporation_ticker
        Map.has_key?(character, :__struct__) &&
          character.__struct__ == WandererNotifier.Data.Character && character.corporation_ticker ->
          Logger.debug("[Formatter] Found corporation ticker in Character struct")
          character.corporation_ticker

        # Standard API format with nested character object and corporation_ticker
        is_map(character["character"]) &&
            Map.has_key?(character["character"], "corporation_ticker") ->
          Logger.debug(
            "[Formatter] Found corporation ticker in standard API format (character.corporation_ticker)"
          )

          character["character"]["corporation_ticker"]

        # Direct corporation_ticker (notification format)
        Map.has_key?(character, "corporation_ticker") ->
          Logger.debug("[Formatter] Found corporation ticker in notification format")
          character["corporation_ticker"]

        # Legacy corporation_name key (backwards compatibility)
        Map.has_key?(character, "corporation_name") ->
          Logger.debug("[Formatter] Found legacy corporation_name in notification format")
          character["corporation_name"]

        # Check for corporation_name in character object
        is_map(character["character"]) && Map.has_key?(character["character"], "corporation_name") ->
          Logger.debug(
            "[Formatter] Found corporation_name in standard API format (character.corporation_name)"
          )

          character["character"]["corporation_name"]

        # Character struct with corporation_name atom key
        Map.has_key?(character, :corporation_name) ->
          Logger.debug("[Formatter] Found corporation_name in Character struct")
          character.corporation_name

        true ->
          Logger.debug("[Formatter] Corporation name not found in data, trying ESI lookup")
          # If no corporation name is available, try the ESI lookup if we have corporation_id
          corporation_id = extract_corporation_id(character)

          if corporation_id do
            Logger.debug(
              "[Formatter] Attempting ESI lookup with corporation_id: #{corporation_id}"
            )

            lookup_corporation_name_from_esi(corporation_id)
          else
            Logger.warning("[Formatter] No corporation_id available for ESI lookup")
            nil
          end
      end

    if is_nil(corporation_name) || corporation_name == "" do
      Logger.debug("[Formatter] Using default corporation name: #{default}")
      default
    else
      corporation_name
    end
  end

  # Helper function to look up corporation name from ESI
  defp lookup_corporation_name_from_esi(corporation_id) do
    if is_binary(corporation_id) || is_integer(corporation_id) do
      try do
        case WandererNotifier.Api.ESI.Service.get_corporation_info(corporation_id) do
          {:ok, corp_data} when is_map(corp_data) ->
            Map.get(corp_data, "name")

          _ ->
            nil
        end
      rescue
        _ -> nil
      end
    else
      nil
    end
  end

  @doc """
  Checks if a string is a valid numeric ID.

  ## Parameters
  - id: The string to check

  ## Returns
  true if the string is a valid numeric ID, false otherwise
  """
  def is_valid_numeric_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end

  def is_valid_numeric_id?(_), do: false
end
