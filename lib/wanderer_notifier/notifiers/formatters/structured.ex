defmodule WandererNotifier.Notifiers.Formatters.Structured do
  @moduledoc """
  Structured notification formatting utilities for Discord notifications.

  This module provides standardized formatting specifically designed to work with
  the domain data structures like Character, MapSystem, and Killmail.
  It eliminates the complex extraction logic of the original formatter by relying
  on the structured data provided by these schemas.
  """

  alias WandererNotifier.Character.Character
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.{Keys, Repository}
  alias WandererNotifier.Notifiers.Discord.Constants

  # Get configured services
  defp zkill_service, do: Application.get_env(:wanderer_notifier, :zkill_service)
  defp esi_service, do: Application.get_env(:wanderer_notifier, :esi_service)

  # Get colors from Constants
  defp colors, do: Constants.colors()

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

  @doc """
  Creates a standard formatted character notification embed/attachment from a Character struct.
  Returns data in a generic format that can be converted to platform-specific format.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_character_notification(%Character{} = character) do
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
  Creates a standard formatted system notification embed/attachment from a MapSystem struct.
  Returns data in a generic format that can be converted to platform-specific format.

  ## Parameters
    - system: The MapSystem struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_system_notification(%MapSystem{} = system) do
    # Log the system data for debugging
    log_system_data(system)

    # Extract basic system information
    system_info = extract_system_info(system)

    # Build notification fields
    fields = build_system_notification_fields(system_info)

    # Build a platform-agnostic structure
    build_system_notification(system_info, fields)
  end

  # Private helper functions

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

  defp log_system_data(system) do
    AppLogger.processor_debug(
      "[StructuredFormatter] Formatting system: #{inspect(system, limit: 200)}"
    )
  end

  defp extract_victim_info(killmail) do
    victim = Killmail.get_victim(killmail) || %{}

    victim_name = Map.get(victim, "character_name", "Unknown Pilot")
    victim_ship = Map.get(victim, "ship_type_name", "Unknown Ship")
    victim_corp = Map.get(victim, "corporation_name", "Unknown Corp")
    victim_alliance = Map.get(victim, "alliance_name")
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
    system_name = Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")
    system_id = Map.get(killmail.esi_data || %{}, "solar_system_id")

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

  defp extract_system_info(system) do
    %{
      name: system.name,
      system_id: system.system_id,
      region_name: system.region_name,
      security_status: system.security_status,
      class_title: system.class_title,
      effect_name: system.effect_name,
      is_shattered: system.is_shattered,
      statics: system.statics
    }
  end

  defp get_final_blow_details(killmail) do
    final_blow =
      killmail.esi_data
      |> Map.get("attackers", [])
      |> Enum.find(&Map.get(&1, "final_blow", false))

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
          name: Map.get(attacker, "character_name", "Unknown"),
          ship: Map.get(attacker, "ship_type_name", "Unknown Ship"),
          corp: Map.get(attacker, "corporation_name", "Unknown Corp"),
          alliance: Map.get(attacker, "alliance_name"),
          ship_type_id: Map.get(attacker, "ship_type_id"),
          character_id: Map.get(attacker, "character_id"),
          weapon: Map.get(attacker, "weapon_type_name", "Unknown Weapon")
        }
    end
  end

  defp build_kill_notification_fields(victim_info, kill_context, final_blow_details) do
    [
      %{
        name: "Victim",
        value: format_entity_info(victim_info),
        inline: true
      },
      %{
        name: "Final Blow",
        value: format_entity_info(final_blow_details),
        inline: true
      },
      %{
        name: "Location",
        value: format_location_info(kill_context),
        inline: true
      },
      %{
        name: "Details",
        value: format_kill_details(kill_context),
        inline: true
      }
    ]
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

  defp build_system_notification_fields(system_info) do
    [
      %{
        name: "System",
        value: format_system_details(system_info),
        inline: true
      },
      %{
        name: "Region",
        value: format_region_details(system_info),
        inline: true
      },
      %{
        name: "Properties",
        value: format_system_properties(system_info),
        inline: true
      }
    ]
  end

  defp build_kill_notification(
         kill_id,
         kill_time,
         victim_info,
         kill_context,
         final_blow_details,
         fields
       ) do
    title = "Kill Report: #{victim_info.name}"
    description = "#{victim_info.name} lost their #{victim_info.ship}"

    color =
      case kill_context.security_status do
        sec when is_number(sec) and sec >= 0.5 -> colors().highsec
        sec when is_number(sec) and sec > 0.0 -> colors().lowsec
        sec when is_number(sec) and sec <= 0.0 -> colors().nullsec
        _ -> colors().default
      end

    %{
      title: title,
      description: description,
      url: "https://zkillboard.com/kill/#{kill_id}/",
      color: color,
      timestamp: kill_time,
      fields: fields,
      footer: %{
        text: "Kill Report"
      },
      thumbnail: %{
        url: get_ship_image_url(victim_info.ship_type_id)
      }
    }
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

  defp build_system_notification(system_info, fields) do
    title = "New System Tracked: #{system_info.name}"
    description = "A new system has been added to tracking"

    color =
      case system_info do
        %{class_title: class} when not is_nil(class) -> colors().wormhole
        %{security_status: sec} when is_number(sec) and sec >= 0.5 -> colors().highsec
        %{security_status: sec} when is_number(sec) and sec > 0.0 -> colors().lowsec
        %{security_status: sec} when is_number(sec) and sec <= 0.0 -> colors().nullsec
        _ -> colors().default
      end

    %{
      title: title,
      description: description,
      color: color,
      fields: fields,
      footer: %{
        text: "System Tracking"
      },
      thumbnail: %{
        url: get_system_image_url(system_info)
      }
    }
  end

  defp format_entity_info(%{name: name, corp: corp, alliance: alliance}) do
    [
      name,
      corp,
      alliance
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_location_info(%{system_name: system, security_formatted: security}) do
    "System: #{system}\nSecurity: #{security}"
  end

  defp format_kill_details(%{formatted_value: value, attackers_count: count, is_npc_kill: is_npc}) do
    npc_text = if is_npc, do: "\nNPC Kill", else: ""
    "Value: #{value}\nAttackers: #{count}#{npc_text}"
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

  defp format_system_details(%{name: name, security_status: security, class_title: class}) do
    class_text = if class, do: "\nClass: #{class}", else: ""
    "Name: #{name}\nSecurity: #{format_security_status(security)}#{class_text}"
  end

  defp format_region_details(%{region_name: region}) do
    "Region: #{region || "Unknown"}"
  end

  defp format_system_properties(%{effect_name: effect, is_shattered: shattered, statics: statics}) do
    effect_text = if effect, do: "Effect: #{effect}\n", else: ""
    shattered_text = if shattered, do: "Shattered System\n", else: ""
    statics_text = if statics, do: "Statics: #{Enum.join(statics, ", ")}", else: ""

    "#{effect_text}#{shattered_text}#{statics_text}"
    |> String.trim()
  end

  defp format_security_status(nil), do: "Unknown"

  defp format_security_status(security) when is_number(security) do
    cond do
      security >= 0.5 -> "#{Float.round(security, 1)} HS"
      security > 0.0 -> "#{Float.round(security, 1)} LS"
      security <= 0.0 -> "#{Float.round(security, 1)} NS"
      true -> "Unknown"
    end
  end

  defp format_security_status(_), do: "Unknown"

  defp format_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 ->
        "#{Float.round(value / 1_000_000_000, 1)}B ISK"

      value >= 1_000_000 ->
        "#{Float.round(value / 1_000_000, 1)}M ISK"

      value >= 1_000 ->
        "#{Float.round(value / 1_000, 1)}K ISK"

      true ->
        "#{Float.round(value, 0)} ISK"
    end
  end

  defp format_isk_value(_), do: "Unknown ISK"

  defp get_ship_image_url(nil), do: "https://images.evetech.net/types/0/render"
  defp get_ship_image_url(ship_id), do: "https://images.evetech.net/types/#{ship_id}/render"

  defp get_character_image_url(nil), do: "https://images.evetech.net/characters/1/portrait"

  defp get_character_image_url(char_id),
    do: "https://images.evetech.net/characters/#{char_id}/portrait"

  defp get_system_image_url(%{class_title: class}) when not is_nil(class) do
    "https://images.evetech.net/types/45041/icon"
  end

  defp get_system_image_url(%{security_status: sec}) when is_number(sec) do
    cond do
      sec >= 0.5 -> "https://images.evetech.net/types/3802/icon"
      sec > 0.0 -> "https://images.evetech.net/types/3796/icon"
      sec <= 0.0 -> "https://images.evetech.net/types/3799/icon"
      true -> "https://images.evetech.net/types/3802/icon"
    end
  end

  defp get_system_image_url(_), do: "https://images.evetech.net/types/3802/icon"
end
