defmodule WandererNotifier.Notifiers.Formatters.Common do
  @moduledoc """
  Common notification formatting utilities for Discord notifications.
  Provides standardized formatting for domain data structures like Character, MapSystem, and Killmail.
  """

  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Notifiers.Formatters.System, as: SystemFormatter

  # Color constants for Discord notifications
  @default_color 0x3498DB
  @success_color 0x2ECC71
  @warning_color 0xF39C12
  @error_color 0xE74C3C
  @info_color 0x3498DB

  @wormhole_color 0x428BCA
  @highsec_color 0x5CB85C
  @lowsec_color 0xE28A0D
  @nullsec_color 0xD9534F

  @doc """
  Returns a standardized set of colors for notification embeds.
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
  """
  def convert_color(color) when is_atom(color), do: Map.get(colors(), color, @default_color)
  def convert_color(color) when is_integer(color), do: color
  def convert_color("#" <> hex) do
    {color, _} = Integer.parse(hex, 16)
    color
  end
  def convert_color(_color), do: @default_color

  @doc """
  Creates a standard formatted character notification embed/attachment from a Character struct.
  Returns data in a generic format that can be converted to platform-specific format.
  """
  def format_character_notification(%MapCharacter{} = character) do
    WandererNotifier.Notifiers.Formatters.Character.format_character_notification(character)
  end

  @doc """
  Creates a standard formatted system notification from a MapSystem struct.
  """
  def format_system_notification(%MapSystem{} = system) do
    SystemFormatter.format_system_notification(system)
  end

  @doc """
  Converts a generic notification structure to Discord's specific format.
  This is the interface between our internal notification format and Discord's requirements.
  """
  def to_discord_format(notification) do
    components = Map.get(notification, :components, [])

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

    add_components_if_present(embed, components)
  end

  defp add_components_if_present(embed, []), do: embed
  defp add_components_if_present(embed, components), do: Map.put(embed, "components", components)
end
