defmodule WandererNotifier.Notifiers.Formatters.Structured do
  @moduledoc """
  Structured notification formatting utilities for Discord notifications.

  This module provides standardized formatting specifically designed to work with
  the domain data structures like Character, MapSystem, and Killmail.
  It eliminates the complex extraction logic of the original formatter by relying
  on the structured data provided by these schemas.
  """

  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.{CachexImpl, Keys}
  alias WandererNotifier.Notifiers.Discord.Constants
  alias WandererNotifier.Notifiers.Formatters.System, as: SystemFormatter

  # Color constants for Discord notifications
  @default_color 0x3498DB
  @success_color 0x2ECC71
  @warning_color 0xF39C12
  @error_color 0xE74C3C
  @info_color 0x3498DB

  # Wormhole and security colors
  @wormhole_color 0x428BCA
  @highsec_color 0x5CB85C
  @lowsec_color 0xE28A0D
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
    fields = build_kill_notification_fields(killmail, kill_context)

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

  @doc """
  Creates a standard formatted character notification embed/attachment from a Character struct.
  Returns data in a generic format that can be converted to platform-specific format.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_character_notification(%MapCharacter{} = character) do
    # Log the character data for debugging
    log_character_data(character)

    # Extract basic character information
    character_info = extract_character_info(character)

    # Build notification fields
    fields = build_character_notification_fields(character_info)

    # Build a platform-agnostic structure
    build_character_notification(character_info, fields)
  end

  @doc """
  Creates a standard formatted system notification from a MapSystem struct.

  ## Parameters
    - system: The MapSystem struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_system_notification(%MapSystem{} = system) do
    SystemFormatter.format_system_notification(system)
  end

  @doc """
  Formats a character kill notification into a generic format.
  """
  def format_character_kill_notification(killmail, character_id, character_name) do
    %{
      title: "Character Kill Report: #{character_name}",
      description: build_character_kill_description(killmail, character_id),
      url: "https://zkillboard.com/kill/#{killmail.killmail_id}/",
      color: Constants.colors().info,
      fields: build_character_kill_fields(killmail, character_id)
    }
  end

  @doc """
  Formats a system activity notification into a generic format.
  """
  def format_system_activity_notification(system, activity_data) do
    %{
      title: "System Activity Update: #{system.name}",
      description: build_system_activity_description(activity_data),
      color: Constants.colors().warning,
      fields: build_system_activity_fields(activity_data)
    }
  end

  @doc """
  Formats a character activity notification into a generic format.
  """
  def format_character_activity_notification(character, activity_data) do
    %{
      title: "Character Activity Update: #{character.name}",
      description: build_character_activity_description(activity_data),
      color: Constants.colors().info,
      fields: build_character_activity_fields(activity_data)
    }
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

    # Convert to Discord embed format with safe field access
    embed = %{
      "title" => Map.get(notification, :title, ""),
      "description" => Map.get(notification, :description, ""),
      "color" => Map.get(notification, :color, @default_color),
      "url" => Map.get(notification, :url),
      "timestamp" => Map.get(notification, :timestamp),
      "footer" => Map.get(notification, :footer),
      "thumbnail" => Map.get(notification, :thumbnail),
      "image" => Map.get(notification, :image),
      "author" => Map.get(notification, :author),
      "fields" =>
        case Map.get(notification, :fields) do
          fields when is_list(fields) ->
            Enum.map(fields, fn field ->
              %{
                "name" => Map.get(field, :name, ""),
                "value" => Map.get(field, :value, ""),
                "inline" => Map.get(field, :inline, false)
              }
            end)
          _ ->
            []
        end
    }

    # Add components if present
    add_components_if_present(embed, components)
  end

  # Private helper functions

  # Helper to add components if present
  defp add_components_if_present(embed, []), do: embed
  defp add_components_if_present(embed, components), do: Map.put(embed, "components", components)

  defp log_killmail_data(killmail) do
    AppLogger.processor_debug(
      "[StructuredFormatter] Formatting killmail: #{inspect(killmail, limit: 200)}"
    )
  end

  defp log_character_data(character) do
    AppLogger.processor_debug(
      "[StructuredFormatter] Formatting character: #{inspect(character, limit: 200)}"
    )
  end


  defp extract_victim_info(killmail) do
    victim = Killmail.get_victim(killmail) || %{}

    victim_name = killmail.victim_name || Map.get(victim, "character_name", "Unknown Pilot")
    victim_ship = killmail.ship_name || Map.get(victim, "ship_type_name", "Unknown Ship")
    victim_corp = killmail.victim_corporation || Map.get(victim, "corporation_name", "Unknown Corp")
    victim_alliance = killmail.victim_alliance || Map.get(victim, "alliance_name")
    victim_ship_type_id = Map.get(victim, "ship_type_id")
    victim_character_id = Map.get(victim, "character_id")

    %{
      name: victim_name,
      ship: victim_ship,
      corp: victim_corp,
      alliance: victim_alliance,
      ship_type_id: victim_ship_type_id,
      character_id: victim_character_id
    }
  end

  defp extract_kill_context(killmail) do
    system_name = killmail.system_name || Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")
    system_id = killmail.system_id || Map.get(killmail.esi_data || %{}, "solar_system_id")

    security_status = get_system_security_status(system_id)
    security_formatted = format_security_status(security_status)

    zkb = killmail.zkb || %{}
    kill_value = Map.get(zkb, "totalValue", 0)
    formatted_value = format_isk_value(kill_value)

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

  defp get_system_security_status(system_id) when is_integer(system_id) do
    case CachexImpl.get(Keys.system_key(system_id)) do
      {:ok, system_data} -> Map.get(system_data, "security_status", 0.0)
      _ -> 0.0
    end
  end

  defp get_system_security_status(_), do: 0.0

  defp extract_character_info(character) do
    %{
      name: character.name,
      character_id: character.character_id,
      corporation_name: character.corporation_name,
      alliance_name: character.alliance_name,
      security_status: character.security_status,
      last_location: character.last_location,
      ship_type: character.ship_type
    }
  end

  defp get_final_blow_details(killmail) do
    final_blow =
      (killmail.attackers || [])
      |> Enum.find(&(&1[:final_blow] == true))

    case final_blow do
      nil ->
        %{
          name: "Unknown",
          ship: "Unknown Ship",
          corp: "Unknown Corp",
          alliance: nil,
          ship_type_id: nil,
          character_id: nil,
          weapon: "Unknown Weapon"
        }

      attacker ->
        %{
          name: attacker[:character_name] || "Unknown",
          ship: attacker[:ship_type_name] || "Unknown Ship",
          corp: attacker[:corporation_name] || "Unknown Corp",
          alliance: attacker[:alliance_name],
          ship_type_id: attacker[:ship_type_id],
          character_id: attacker[:character_id],
          weapon: attacker[:weapon_type_name] || "Unknown Weapon"
        }
    end
  end

  defp build_kill_notification_fields(_killmail, kill_context) do
    [
      %{
        name: "System",
        value: "#{kill_context.system_name} (#{kill_context.security_formatted})",
        inline: true
      },
      %{
        name: "Attackers",
        value: "#{kill_context.attackers_count}",
        inline: true
      },
      %{
        name: "Value",
        value: kill_context.formatted_value,
        inline: true
      }
    ]
  end

  defp build_kill_notification(
         kill_id,
         kill_time,
         victim_info,
         kill_context,
         _final_blow_details,
         fields
       ) do
    %{
      title: "Kill Report: #{victim_info.name}",
      description:
        "#{victim_info.name} lost their #{victim_info.ship} in #{kill_context.system_name} (#{kill_context.security_formatted})",
      url: "https://zkillboard.com/kill/#{kill_id}/",
      timestamp: kill_time,
      color: get_notification_color(kill_context.security_status),
      fields: fields,
      footer: %{
        text: "Value: #{kill_context.formatted_value} ISK"
      }
    }
  end

  defp build_character_notification_fields(character_info) do
    [
      %{
        name: "Character",
        value: format_character_details(character_info),
        inline: true
      },
      %{
        name: "Corporation",
        value: format_corporation_details(character_info),
        inline: true
      },
      %{
        name: "Location",
        value: format_character_location(character_info),
        inline: true
      }
    ]
  end

  defp build_character_notification(character_info, fields) do
    title = "New Character Tracked: #{character_info.name}"
    description = "A new character has been added to tracking"

    color =
      case character_info.security_status do
        sec when is_number(sec) and sec >= 5.0 -> colors().highsec
        sec when is_number(sec) and sec > 0.0 -> colors().lowsec
        sec when is_number(sec) and sec <= 0.0 -> colors().nullsec
        _ -> colors().default
      end

    %{
      title: title,
      description: description,
      url: "https://zkillboard.com/character/#{character_info.character_id}/",
      color: color,
      fields: fields,
      footer: %{
        text: "Character Tracking"
      },
      thumbnail: %{
        url: get_character_image_url(character_info.character_id)
      }
    }
  end

  defp format_character_details(%{name: name, security_status: security}) do
    security_text = format_security_status(security)
    "Name: #{name}\nSecurity: #{security_text}"
  end

  defp format_corporation_details(%{corporation_name: corp, alliance_name: alliance}) do
    alliance_text = if alliance, do: "\nAlliance: #{alliance}", else: ""
    "Corporation: #{corp}#{alliance_text}"
  end

  defp format_character_location(%{last_location: location, ship_type: ship}) do
    ship_text = if ship, do: "\nShip: #{ship}", else: ""
    "Location: #{location || "Unknown"}#{ship_text}"
  end

  defp format_security_status(security_status) when is_float(security_status) do
    cond do
      security_status >= 0.5 -> "High Sec"
      security_status > 0.0 -> "Low Sec"
      true -> "Null Sec"
    end
  end

  defp format_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K"
      true -> "#{Float.round(value, 0)}"
    end
  end

  defp get_character_image_url(nil), do: "https://images.evetech.net/characters/1/portrait"

  defp get_character_image_url(character_id),
    do: "https://images.evetech.net/characters/#{character_id}/portrait"


  defp get_notification_color(%{security_status: sec}) when is_number(sec) do
    case sec do
      sec when sec >= 0.5 -> colors().highsec
      sec when sec > 0.0 -> colors().lowsec
      sec when sec <= 0.0 -> colors().nullsec
      _ -> colors().default
    end
  end

  defp get_notification_color(_), do: colors().default

  defp build_character_kill_description(killmail, character_id) do
    victim = Map.get(killmail.esi_data || %{}, "victim", %{})
    attacker_info = find_character_in_attackers(killmail, character_id)

    case {victim["character_id"] == character_id, attacker_info} do
      {true, _} -> "Lost a ship"
      {false, nil} -> "Was involved in a kill"
      {false, info} -> "Got a kill (#{info["damage_done"]} damage)"
    end
  end

  defp find_character_in_attackers(killmail, character_id) do
    attackers = Map.get(killmail.esi_data || %{}, "attackers", [])
    Enum.find(attackers, &(Map.get(&1, "character_id") == character_id))
  end

  defp build_character_kill_fields(killmail, character_id) do
    victim = Map.get(killmail.esi_data || %{}, "victim", %{})
    attacker_info = find_character_in_attackers(killmail, character_id)

    case {victim["character_id"] == character_id, attacker_info} do
      {true, _} -> build_victim_fields(victim)
      {false, info} when is_map(info) -> build_attacker_fields(info)
      _ -> []
    end
  end

  defp build_victim_fields(victim) do
    [
      %{
        name: "Ship Lost",
        value: victim["ship_type_name"] || "Unknown Ship",
        inline: true
      }
    ]
  end

  defp build_attacker_fields(attacker) do
    [
      %{
        name: "Ship Used",
        value: attacker["ship_type_name"] || "Unknown Ship",
        inline: true
      },
      %{
        name: "Damage Done",
        value: "#{attacker["damage_done"]}",
        inline: true
      }
    ]
  end

  defp build_system_activity_description(activity_data) do
    kills = Map.get(activity_data, "kills", 0)
    jumps = Map.get(activity_data, "jumps", 0)
    "Activity in the last hour: #{kills} kills, #{jumps} jumps"
  end

  defp build_system_activity_fields(activity_data) do
    [
      %{
        name: "Kills",
        value: "#{Map.get(activity_data, "kills", 0)}",
        inline: true
      },
      %{
        name: "Jumps",
        value: "#{Map.get(activity_data, "jumps", 0)}",
        inline: true
      }
    ]
  end

  defp build_character_activity_description(activity_data) do
    kills = Map.get(activity_data, "kills", 0)
    losses = Map.get(activity_data, "losses", 0)
    "Activity in the last hour: #{kills} kills, #{losses} losses"
  end

  defp build_character_activity_fields(activity_data) do
    [
      %{
        name: "Kills",
        value: "#{Map.get(activity_data, "kills", 0)}",
        inline: true
      },
      %{
        name: "Losses",
        value: "#{Map.get(activity_data, "losses", 0)}",
        inline: true
      }
    ]
  end

  def format_system_status_message(
        title,
        description,
        websocket,
        uptime,
        extra,
        status,
        systems_count,
        characters_count
      ) do
    %{
      title: title,
      description: description,
      websocket: websocket,
      uptime: uptime,
      extra: extra,
      status: status,
      systems_count: systems_count,
      characters_count: characters_count
    }
  end
end
