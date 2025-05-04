defmodule WandererNotifier.Notifiers.Formatters.Structured do
  @moduledoc """
  Structured notification formatting utilities for Discord notifications.

  This module provides standardized formatting specifically designed to work with
  the domain data structures like Character, MapSystem, and Killmail.
  It eliminates the complex extraction logic of the original formatter by relying
  on the structured data provided by these schemas.
  """

  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Map.MapSystem
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
  Creates a standard formatted character notification embed/attachment from a Character struct.
  Returns data in a generic format that can be converted to platform-specific format.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_character_notification(%MapCharacter{} = character) do
    WandererNotifier.Notifiers.Formatters.Character.format_character_notification(character)
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

    require Logger
    Logger.info("[StructuredFormatter] to_discord_format input", notification: inspect(notification))

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

    Logger.info("[StructuredFormatter] to_discord_format output", embed: inspect(embed))

    # Add components if present
    add_components_if_present(embed, components)
  end

  # Private helper functions

  # Helper to add components if present
  defp add_components_if_present(embed, []), do: embed
  defp add_components_if_present(embed, components), do: Map.put(embed, "components", components)

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
