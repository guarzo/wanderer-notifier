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
    character_id = extract_character_id(character)
    character_name = extract_character_name(character)
    corporation_name = extract_corporation_name(character)
    corporation_id = extract_corporation_id(character)

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
    # Extract all system information
    Logger.info("Original system data: #{inspect(system, pretty: true, limit: 5000)}")
    system = normalize_system_data(system)
    Logger.info("Normalized system data: #{inspect(system, pretty: true, limit: 5000)}")

    # Check if system contains a system object and log its contents
    system_obj = Map.get(system, "system") || Map.get(system, :system)

    if system_obj do
      Logger.info("System object found with keys: #{inspect(Map.keys(system_obj))}")

      if is_struct(system_obj) do
        Logger.info(
          "System object is a struct with original_name: #{system_obj.original_name}, temporary_name: #{inspect(system_obj.temporary_name)}"
        )
      else
        orig = Map.get(system_obj, "original_name") || Map.get(system_obj, :original_name)
        temp = Map.get(system_obj, "temporary_name") || Map.get(system_obj, :temporary_name)

        Logger.info(
          "System object is a map with original_name: #{inspect(orig)}, temporary_name: #{inspect(temp)}"
        )
      end
    end

    # Get system ID from multiple possible locations
    system_id =
      Map.get(system, "solar_system_id") ||
        Map.get(system, :solar_system_id) ||
        Map.get(system, "system_id") ||
        Map.get(system, :system_id) ||
        Map.get(system, "id") ||
        Map.get(system, :id) ||
        Map.get(system, "systemId") ||
        Map.get(system, :systemId)

    # Get system name from multiple possible locations,
    # prioritizing system object fields
    orig_name =
      get_in(system, ["system", "original_name"]) ||
        get_in(system, [:system, :original_name]) ||
        Map.get(system, "original_name") ||
        Map.get(system, :original_name)

    temp_name =
      get_in(system, ["system", "temporary_name"]) ||
        get_in(system, [:system, :temporary_name]) ||
        Map.get(system, "temporary_name") ||
        Map.get(system, :temporary_name)

    # Get basic name from various sources
    basic_name =
      get_in(system, ["system", "name"]) ||
        get_in(system, [:system, :name]) ||
        Map.get(system, "display_name") ||
        Map.get(system, :display_name) ||
        Map.get(system, "solar_system_name") ||
        Map.get(system, :solar_system_name) ||
        Map.get(system, "system_name") ||
        Map.get(system, :system_name) ||
        Map.get(system, "systemName") ||
        Map.get(system, :systemName) ||
        Map.get(system, "name") ||
        Map.get(system, :name) ||
        "Unknown System"

    Logger.info(
      "[Formatter] Name values - orig_name: #{inspect(orig_name)}, temp_name: #{inspect(temp_name)}, basic_name: #{inspect(basic_name)}"
    )

    # Set the final system name, with preference for combination of temporary and original
    system_name =
      if temp_name && temp_name != "" && orig_name && orig_name != "" do
        formatted_name = "#{temp_name} (#{orig_name})"

        Logger.info(
          "[Formatter] Using combined temporary_name and original_name: #{formatted_name}"
        )

        formatted_name
      else
        if orig_name && orig_name != "" do
          Logger.info("[Formatter] Using just original_name: #{orig_name}")
          orig_name
        else
          Logger.info("[Formatter] Falling back to basic_name: #{basic_name}")
          basic_name
        end
      end

    # Get type description from multiple possible locations
    type_description =
      Map.get(system, "type_description") ||
        Map.get(system, :type_description) ||
        get_in(system, ["staticInfo", "typeDescription"]) ||
        get_in(system, [:staticInfo, :typeDescription]) ||
        Map.get(system, "typeDescription") ||
        Map.get(system, :typeDescription)

    # Get class title for wormhole systems from multiple possible locations
    # First prioritize the system object's class_title
    # Then the top-level class_title
    # Fall back to other sources
    class_title =
      get_in(system, ["system", "class_title"]) ||
        get_in(system, [:system, :class_title]) ||
        Map.get(system, "class_title") ||
        Map.get(system, :class_title) ||
        get_in(system, ["staticInfo", "class_title"]) ||
        get_in(system, [:staticInfo, :class_title])

    Logger.info(
      "System ID: #{system_id}, System Name: #{system_name}, Type Description: #{type_description}"
    )

    if type_description == nil do
      Logger.error(
        "Cannot format system notification: type_description not available for system #{system_name} (ID: #{system_id})"
      )

      nil
    else
      effect_name =
        Map.get(system, "effect_name") ||
          Map.get(system, :effect_name) ||
          get_in(system, ["staticInfo", "effectName"]) ||
          get_in(system, [:staticInfo, :effectName])

      is_shattered =
        Map.get(system, "is_shattered") ||
          Map.get(system, :is_shattered) ||
          get_in(system, ["staticInfo", "isShattered"]) ||
          get_in(system, [:staticInfo, :isShattered])

      statics =
        Map.get(system, "statics") ||
          Map.get(system, :statics) ||
          get_in(system, ["staticInfo", "statics"]) ||
          get_in(system, [:staticInfo, :statics]) ||
          []

      # Ensure statics is always a string for display
      _static_display =
        cond do
          is_binary(statics) && statics != "" -> statics
          is_list(statics) && length(statics) > 0 -> Enum.join(statics, ", ")
          true -> "None"
        end

      region_name =
        Map.get(system, "region_name") ||
          Map.get(system, :region_name) ||
          get_in(system, ["staticInfo", "regionName"]) ||
          get_in(system, [:staticInfo, :regionName])

      # Use class_title for wormholes if available, otherwise fall back to type_description
      is_wormhole =
        String.contains?(type_description || "", "Class") ||
          (class_title != nil &&
             (String.contains?(class_title, "C") || String.contains?(class_title, "Class")))

      # Generate title using class_title for wormholes, type_description for others
      title =
        if is_wormhole && class_title do
          "New #{class_title} System Mapped"
        else
          "New #{type_description} System Mapped"
        end

      # Generate description using class_title for wormholes, type_description for others
      description =
        if is_wormhole && class_title do
          "A #{class_title} wormhole system has been discovered and added to the map."
        else
          "A #{type_description} system has been discovered and added to the map."
        end

      sun_type_id =
        Map.get(system, "sun_type_id") ||
          Map.get(system, :sun_type_id) ||
          get_in(system, ["staticInfo", "sunTypeId"]) ||
          get_in(system, [:staticInfo, :sunTypeId])

      icon_url = determine_system_icon(sun_type_id, effect_name, type_description)

      embed_color = determine_system_color(type_description, is_wormhole)

      # Use system ID if available, otherwise use ID field
      zkill_id =
        if system_id do
          if is_binary(system_id) && String.contains?(system_id, "-") do
            # Handle UUID-style IDs - use system name for link instead
            system_name
          else
            system_id
          end
        else
          system_name
        end

      display_name =
        if is_binary(zkill_id) && String.contains?(zkill_id, "-") do
          # For UUID-style IDs, just show the name without a link
          system_name
        else
          "[#{system_name}](https://zkillboard.com/system/#{zkill_id}/)"
        end

      # Start building fields list
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
          # First try to get static_details which has destination information
          static_details =
            get_in(system, ["static_details"]) ||
              get_in(system, [:static_details]) ||
              get_in(system, ["staticInfo", "static_details"]) ||
              get_in(system, [:staticInfo, :static_details])

          if is_list(static_details) && length(static_details) > 0 do
            statics_str = format_statics_list(static_details)
            Logger.info("[Formatter] Adding statics with destination details: #{statics_str}")
            fields ++ [%{name: "Statics", value: statics_str, inline: true}]
          else
            # Fall back to basic statics list if detailed info is not available
            if is_list(statics) && length(statics) > 0 do
              statics_str = format_statics_list(statics)
              Logger.info("[Formatter] Adding statics to system notification: #{statics_str}")
              fields ++ [%{name: "Statics", value: statics_str, inline: true}]
            else
              # Try to find statics from other common locations
              alt_statics =
                get_in(system, ["staticInfo", "statics"]) ||
                  get_in(system, [:staticInfo, :statics]) ||
                  get_in(system, ["data", "statics"]) ||
                  get_in(system, [:data, :statics])

              if is_list(alt_statics) && length(alt_statics) > 0 do
                statics_str = format_statics_list(alt_statics)
                Logger.info("[Formatter] Adding statics from alternative source: #{statics_str}")
                fields ++ [%{name: "Statics", value: statics_str, inline: true}]
              else
                Logger.warning(
                  "[Formatter] Wormhole system without statics: #{system_name}, tried statics=#{inspect(statics)} and alt_statics=#{inspect(alt_statics)}"
                )

                fields
              end
            end
          end
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
    if final_blow_attacker do
      final_blow_name =
        if is_npc_kill,
          do: "NPC",
          else: get_value(final_blow_attacker, ["character_name"], "Unknown Pilot")

      final_blow_ship = get_value(final_blow_attacker, ["ship_type_name"], "Unknown Ship")

      final_blow_character_id =
        Map.get(final_blow_attacker, "character_id") ||
          Map.get(final_blow_attacker, :character_id)

      if final_blow_character_id && !is_npc_kill do
        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: final_blow_character_id,
          text:
            "[#{final_blow_name}](https://zkillboard.com/character/#{final_blow_character_id}/) (#{final_blow_ship})"
        }
      else
        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: nil,
          text: "#{final_blow_name} (#{final_blow_ship})"
        }
      end
    else
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
    # If statics is already a formatted string, just return it
    if is_binary(statics) do
      statics
    else
      # Safely handle nil case
      statics_list = if is_nil(statics), do: [], else: statics

      # Map each static and join with comma
      Enum.map_join(statics_list, ", ", fn static ->
        cond do
          # Handle map with destination information (complete format)
          is_map(static) && Map.has_key?(static, "destination") ->
            name = Map.get(static, "name")
            destination = Map.get(static, "destination") || %{}
            short_name = Map.get(destination, "short_name")

            if name && short_name do
              "#{name} (#{short_name})"
            else
              name || "Unknown"
            end

          # Handle map with name key (common format)
          is_map(static) && (Map.has_key?(static, "name") || Map.has_key?(static, :name)) ->
            Map.get(static, "name") || Map.get(static, :name)

          # Handle map with destination_class key (detailed format)
          is_map(static) &&
              (Map.has_key?(static, "destination_class") ||
                 Map.has_key?(static, :destination_class)) ->
            destination =
              Map.get(static, "destination_class") || Map.get(static, :destination_class)

            wh_code =
              Map.get(static, "wormhole_code") || Map.get(static, :wormhole_code) ||
                Map.get(static, "code") || Map.get(static, :code)

            if wh_code && destination do
              "#{wh_code} → #{destination}"
            else
              wh_code || destination || inspect(static)
            end

          # Handle map with just code field
          is_map(static) &&
              (Map.has_key?(static, "wormhole_code") || Map.has_key?(static, :wormhole_code) ||
                 Map.has_key?(static, "code") || Map.has_key?(static, :code)) ->
            Map.get(static, "wormhole_code") || Map.get(static, :wormhole_code) ||
              Map.get(static, "code") || Map.get(static, :code)

          # Handle simple string static
          is_binary(static) ->
            static

          # Fallback for any other format
          true ->
            inspect(static)
        end
      end)
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
  Extracts a valid EVE character ID from a character map.
  Handles various possible key structures.

  Returns the ID as a string or nil if no valid ID is found.
  """
  def extract_character_id(character) when is_map(character) do
    # Extract character ID - only accept numeric IDs
    cond do
      # Check top level character_id
      is_binary(character["character_id"]) && is_valid_numeric_id?(character["character_id"]) ->
        character["character_id"]

      # Check top level eve_id
      is_binary(character["eve_id"]) && is_valid_numeric_id?(character["eve_id"]) ->
        character["eve_id"]

      # Check nested character object
      is_map(character["character"]) && is_binary(character["character"]["eve_id"]) &&
          is_valid_numeric_id?(character["character"]["eve_id"]) ->
        character["character"]["eve_id"]

      is_map(character["character"]) && is_binary(character["character"]["character_id"]) &&
          is_valid_numeric_id?(character["character"]["character_id"]) ->
        character["character"]["character_id"]

      is_map(character["character"]) && is_binary(character["character"]["id"]) &&
          is_valid_numeric_id?(character["character"]["id"]) ->
        character["character"]["id"]

      # No valid numeric ID found
      true ->
        Logger.error(
          "No valid numeric EVE ID found for character: #{inspect(character, pretty: true, limit: 500)}"
        )

        nil
    end
  end

  @doc """
  Extracts a character name from a character map.
  Handles various possible key structures.

  Returns the name as a string or a default value if no name is found.
  """
  def extract_character_name(character, default \\ "Unknown Character") when is_map(character) do
    cond do
      character["character_name"] != nil ->
        character["character_name"]

      character["name"] != nil ->
        character["name"]

      is_map(character["character"]) && character["character"]["name"] != nil ->
        character["character"]["name"]

      is_map(character["character"]) && character["character"]["character_name"] != nil ->
        character["character"]["character_name"]

      true ->
        character_id = extract_character_id(character)
        if character_id, do: "Character #{character_id}", else: default
    end
  end

  @doc """
  Extracts a corporation name from a character map.
  Handles various possible key structures including fallbacks.

  Returns the name as a string or a default value if no name is found.
  """
  def extract_corporation_name(character, default \\ "Unknown Corporation")
      when is_map(character) do
    corporation_name =
      cond do
        # Direct corporation_name
        character["corporation_name"] != nil ->
          character["corporation_name"]

        # Alternative key corporationName
        character["corporationName"] != nil ->
          character["corporationName"]

        # Nested in character object
        is_map(character["character"]) && character["character"]["corporation_name"] != nil ->
          character["character"]["corporation_name"]

        # Nested with alternate key
        is_map(character["character"]) && character["character"]["corporationName"] != nil ->
          character["character"]["corporationName"]

        # Fall back to corporation ticker as name
        character["corporation_ticker"] != nil ->
          "[#{character["corporation_ticker"]}]"

        # Nested corporation ticker
        is_map(character["character"]) && character["character"]["corporation_ticker"] != nil ->
          "[#{character["character"]["corporation_ticker"]}]"

        # Try to look up from ESI if we have corporation_id
        character["corporation_id"] != nil ->
          lookup_corporation_name_from_esi(character["corporation_id"]) || default

        # Try to look up from nested corporation_id
        is_map(character["character"]) && character["character"]["corporation_id"] != nil ->
          lookup_corporation_name_from_esi(character["character"]["corporation_id"]) || default

        # Try to look up from corporationID (alternative key)
        character["corporationID"] != nil ->
          lookup_corporation_name_from_esi(character["corporationID"]) || default

        # No corporation info found
        true ->
          default
      end

    # Clean up any nil values that might have slipped through
    if is_nil(corporation_name), do: default, else: corporation_name
  end

  @doc """
  Extracts a corporation ID from a character map.
  Handles various possible key structures.

  Returns the ID as a string or nil if no valid ID is found.
  """
  def extract_corporation_id(character) when is_map(character) do
    # Try several possible locations for corporation ID
    cond do
      # Direct corporation_id
      character["corporation_id"] != nil && is_valid_numeric_id?(character["corporation_id"]) ->
        character["corporation_id"]

      # Alternative key corporationID
      character["corporationID"] != nil && is_valid_numeric_id?(character["corporationID"]) ->
        character["corporationID"]

      # Nested in character object with regular key
      is_map(character["character"]) &&
        character["character"]["corporation_id"] != nil &&
          is_valid_numeric_id?(character["character"]["corporation_id"]) ->
        character["character"]["corporation_id"]

      # Nested with alternative key
      is_map(character["character"]) &&
        character["character"]["corporationID"] != nil &&
          is_valid_numeric_id?(character["character"]["corporationID"]) ->
        character["character"]["corporationID"]

      # No valid corporation ID found
      true ->
        nil
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
