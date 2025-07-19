defmodule WandererNotifier.Domains.Notifications.Formatters.Common do
  @moduledoc """
  Common notification formatting utilities for Discord notifications.
  Provides standardized formatting for domain data structures like Character, MapSystem, and Killmail.
  """

  alias WandererNotifier.Domains.CharacterTracking.Character
  alias WandererNotifier.Domains.SystemTracking.System
  alias WandererNotifier.Shared.Types.Constants

  @doc """
  Returns a standardized set of colors for notification embeds.
  """
  def colors do
    %{
      default: Constants.default_embed_color(),
      success: Constants.success_color(),
      warning: Constants.warning_color(),
      error: Constants.error_color(),
      info: Constants.info_color(),
      wormhole: Constants.wormhole_color(),
      highsec: Constants.highsec_color(),
      lowsec: Constants.lowsec_color(),
      nullsec: Constants.nullsec_color()
    }
  end

  @doc """
  Converts a color in one format to Discord format.
  """
  def convert_color(color) when is_atom(color),
    do: Map.get(colors(), color, Constants.default_embed_color())

  def convert_color(color) when is_integer(color), do: color

  def convert_color("#" <> hex) do
    # Convert hex color to integer, use 0 as default
    case Integer.parse(hex, 16) do
      {color, _} -> color
      :error -> Constants.default_embed_color()
    end
  end

  def convert_color(_color), do: Constants.default_embed_color()

  @doc """
  Creates a standard formatted character notification embed/attachment from a Character struct.
  Returns data in a generic format that can be converted to platform-specific format.
  """
  def format_character_notification(%Character{} = character) do
    WandererNotifier.Domains.Notifications.Formatters.Character.format_character_notification(
      character
    )
  end

  @doc """
  Creates a standard formatted system notification from a MapSystem struct.
  """
  def format_system_notification(%System{} = system) do
    WandererNotifier.Domains.Notifications.Formatters.System.format_system_notification(system)
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
      "color" => Map.get(notification, :color, Constants.default_embed_color()),
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
