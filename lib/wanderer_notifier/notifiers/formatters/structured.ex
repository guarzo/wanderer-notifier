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
  Converts a generic notification to Discord format.
  """
  def to_discord_format(generic_notification) do
    color = Map.get(generic_notification, :color, Constants.colors().default)

    %{
      title: generic_notification.title,
      description: generic_notification.description,
      url: Map.get(generic_notification, :url),
      color: color,
      fields: Map.get(generic_notification, :fields, []),
      footer: Map.get(generic_notification, :footer),
      thumbnail: Map.get(generic_notification, :thumbnail)
    }
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

  defp get_system_image_url(%{class_title: class}) when not is_nil(class),
    do: "https://images.evetech.net/types/30881/render"

  defp get_system_image_url(%{security_status: sec}) when is_number(sec) and sec >= 0.5,
    do: "https://images.evetech.net/types/30882/render"

  defp get_system_image_url(%{security_status: sec}) when is_number(sec) and sec > 0.0,
    do: "https://images.evetech.net/types/30883/render"

  defp get_system_image_url(%{security_status: sec}) when is_number(sec) and sec <= 0.0,
    do: "https://images.evetech.net/types/30884/render"

  defp get_system_image_url(_), do: "https://images.evetech.net/types/30885/render"

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
