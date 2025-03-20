defmodule WandererNotifier.Notifiers.Formatter do
  @moduledoc """
  Notification formatting utilities for Discord notifications.
  
  This module provides standardized formatting for various notification types,
  making it easier to maintain consistent notification styles for Discord.
  It handles common formatting tasks and data transformations needed for rich notifications.
  """
  
  require Logger
  
  # Color constants for Discord notifications
  @default_color 0x3498DB    # Default blue
  @success_color 0x2ECC71    # Green
  @warning_color 0xF39C12    # Orange
  @error_color 0xE74C3C      # Red
  @info_color 0x3498DB       # Blue
  
  # Wormhole and security colors
  @wormhole_color 0x428BCA   # Blue for Pulsar
  @highsec_color 0x5CB85C    # Green for highsec
  @lowsec_color 0xE28A0D     # Yellow/orange for lowsec
  @nullsec_color 0xD9534F    # Red for nullsec
  
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
    final_blow_attacker = Enum.find(attackers, fn attacker ->
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
        url: if(victim_ship_type_id, do: "https://images.evetech.net/types/#{victim_ship_type_id}/render", else: nil)
      },
      author: %{
        name: if(victim_name == "Unknown Pilot" and victim_corp == "Unknown Corp") do
          "Kill in #{system_name}"
        else
          "#{victim_name} (#{victim_corp})"
        end,
        icon_url: if(victim_name == "Unknown Pilot" and victim_corp == "Unknown Corp") do
          "https://images.evetech.net/types/30371/icon"
        else
          if(victim_character_id, do: "https://imageserver.eveonline.com/Character/#{victim_character_id}_64.jpg", else: nil)
        end
      },
      fields: [
        %{name: "Value", value: formatted_value, inline: true},
        %{name: "Attackers", value: "#{attackers_count}", inline: true},
        %{name: "Final Blow", value: final_blow_details.text, inline: true}
      ] ++ (if victim_alliance, do: [%{name: "Alliance", value: victim_alliance, inline: true}], else: [])
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
    
    %{
      type: :character_notification,
      title: "New Character Tracked",
      description: "A new character has been added to the tracking list.",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        url: "https://imageserver.eveonline.com/Character/#{character_id}_128.jpg"
      },
      fields: [
        %{
          name: "Character",
          value: "[#{character_name}](https://zkillboard.com/character/#{character_id}/)",
          inline: true
        }
      ] ++ (if corporation_name, do: [%{name: "Corporation", value: corporation_name, inline: true}], else: [])
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
    Logger.debug("Original system data: #{inspect(system, pretty: true, limit: 5000)}")
    system = normalize_system_data(system)
    Logger.debug("Normalized system data: #{inspect(system, pretty: true, limit: 5000)}")
    
    # Get system ID from multiple possible locations
    system_id = Map.get(system, "solar_system_id") || 
                Map.get(system, :solar_system_id) ||
                Map.get(system, "system_id") ||
                Map.get(system, :system_id) ||
                Map.get(system, "id") ||
                Map.get(system, :id) ||
                Map.get(system, "systemId") ||
                Map.get(system, :systemId)
                
    # Get system name from multiple possible locations
    system_name = Map.get(system, "solar_system_name") || 
                  Map.get(system, :solar_system_name) || 
                  Map.get(system, "system_name") || 
                  Map.get(system, :system_name) ||
                  Map.get(system, "systemName") ||
                  Map.get(system, :systemName) ||
                  Map.get(system, "name") ||
                  Map.get(system, :name) ||
                  "Unknown System"
    
    # Get type description from multiple possible locations              
    type_description = Map.get(system, "type_description") || 
                       Map.get(system, :type_description) ||
                       get_in(system, ["staticInfo", "typeDescription"]) ||
                       get_in(system, [:staticInfo, :typeDescription]) ||
                       Map.get(system, "typeDescription") ||
                       Map.get(system, :typeDescription)
    
    Logger.debug("System ID: #{system_id}, System Name: #{system_name}, Type Description: #{type_description}")
                       
    if type_description == nil do
      Logger.error("Cannot format system notification: type_description not available for system #{system_name} (ID: #{system_id})")
      nil
    else
      effect_name = Map.get(system, "effect_name") || 
                    Map.get(system, :effect_name) ||
                    get_in(system, ["staticInfo", "effectName"]) ||
                    get_in(system, [:staticInfo, :effectName])
                    
      is_shattered = Map.get(system, "is_shattered") || 
                     Map.get(system, :is_shattered) ||
                     get_in(system, ["staticInfo", "isShattered"]) ||
                     get_in(system, [:staticInfo, :isShattered])
                     
      statics = Map.get(system, "statics") || 
                Map.get(system, :statics) || 
                get_in(system, ["staticInfo", "statics"]) ||
                get_in(system, [:staticInfo, :statics]) ||
                []
                
      region_name = Map.get(system, "region_name") || 
                    Map.get(system, :region_name) ||
                    get_in(system, ["staticInfo", "regionName"]) ||
                    get_in(system, [:staticInfo, :regionName])
      
      title = "New #{type_description} System Mapped"
      description = "A #{type_description} system has been discovered and added to the map."
      
      is_wormhole = String.contains?(type_description, "Class")
      sun_type_id = Map.get(system, "sun_type_id") || 
                    Map.get(system, :sun_type_id) ||
                    get_in(system, ["staticInfo", "sunTypeId"]) ||
                    get_in(system, [:staticInfo, :sunTypeId])
      
      icon_url = determine_system_icon(sun_type_id, effect_name, type_description)
      
      embed_color = determine_system_color(type_description, is_wormhole)
      
      # Use system ID if available, otherwise use ID field
      zkill_id = if system_id do
        if is_binary(system_id) && String.contains?(system_id, "-") do
          # Handle UUID-style IDs - use system name for link instead
          system_name
        else
          system_id
        end
      else
        system_name
      end
      
      display_name = if is_binary(zkill_id) && String.contains?(zkill_id, "-") do
        # For UUID-style IDs, just show the name without a link
        system_name
      else
        "[#{system_name}](https://zkillboard.com/system/#{zkill_id}/)"
      end
      
      # Start building fields list
      fields = [%{name: "System", value: display_name, inline: true}]
      
      # Add shattered field if applicable
      fields = if is_wormhole && is_shattered do
        fields ++ [%{name: "Shattered", value: "Yes", inline: true}]
      else
        fields
      end
      
      # Add statics field if applicable
      fields = if is_wormhole && is_list(statics) && length(statics) > 0 do
        statics_str = format_statics_list(statics)
        fields ++ [%{name: "Statics", value: statics_str, inline: true}]
      else
        fields
      end
      
      # Add region field if available
      fields = if region_name do
        encoded_region_name = URI.encode(region_name)
        region_link = "[#{region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"
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
      "fields" => Enum.map(notification.fields || [], fn field ->
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
      final_blow_name = if is_npc_kill, 
        do: "NPC", 
        else: get_value(final_blow_attacker, ["character_name"], "Unknown Pilot")
        
      final_blow_ship = get_value(final_blow_attacker, ["ship_type_name"], "Unknown Ship")
      
      final_blow_character_id = Map.get(final_blow_attacker, "character_id") ||
                                Map.get(final_blow_attacker, :character_id)
                                
      if final_blow_character_id && !is_npc_kill do
        %{
          name: final_blow_name,
          ship: final_blow_ship,
          character_id: final_blow_character_id,
          text: "[#{final_blow_name}](https://zkillboard.com/character/#{final_blow_character_id}/) (#{final_blow_ship})"
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
      String.contains?(type_description, "High-sec") -> @highsec_color
      String.contains?(type_description, "Low-sec") -> @lowsec_color
      String.contains?(type_description, "Null-sec") -> @nullsec_color
      is_wormhole -> @wormhole_color
      true -> @default_color
    end
  end
  
  # Helper to format a list of statics
  defp format_statics_list(statics) do
    Enum.map_join(statics, ", ", fn static ->
      cond do
        is_map(static) ->
          Map.get(static, "name") || Map.get(static, :name) || inspect(static)
          
        is_binary(static) ->
          static
          
        true ->
          inspect(static)
      end
    end)
  end
  
  # Helper to normalize system data by merging nested data if present
  defp normalize_system_data(system) do
    # First merge data if it exists
    system = if Map.has_key?(system, "data") and is_map(system["data"]) do
      Map.merge(system, system["data"])
    else
      system
    end
    
    # Handle staticInfo data structure common in the API
    if Map.has_key?(system, "staticInfo") and is_map(system["staticInfo"]) do
      static_info = system["staticInfo"]
      
      # Extract key information from staticInfo
      system = if Map.has_key?(static_info, "typeDescription") do
        Map.put(system, "type_description", static_info["typeDescription"])
      else
        system
      end
      
      # Extract statics if they exist
      system = if Map.has_key?(static_info, "statics") do
        Map.put(system, "statics", static_info["statics"])
      else
        system
      end
      
      # Copy over system name and ID if available in the parent object
      system = if system["systemName"] && !Map.has_key?(system, "system_name") do
        Map.put(system, "system_name", system["systemName"])
      else
        system
      end
      
      system = if system["systemId"] && !Map.has_key?(system, "system_id") do
        Map.put(system, "system_id", system["systemId"])
      else
        system
      end
      
      system
    else
      system
    end
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
  Handles various possible key structures.
  
  Returns the name as a string or a default value if no name is found.
  """
  def extract_corporation_name(character, default \\ "Unknown Corporation") when is_map(character) do
    cond do
      character["corporation_name"] != nil ->
        character["corporation_name"]
        
      is_map(character["character"]) && character["character"]["corporation_name"] != nil ->
        character["character"]["corporation_name"]
        
      true ->
        default
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