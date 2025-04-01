defmodule WandererNotifier.Notifications.Formatters.Embed do
  @moduledoc """
  Generic embed formatting utilities.
  Provides functions for creating and manipulating embed structures.
  """

  # Color constants for notifications
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

  def convert_color(_color), do: @default_color

  @doc """
  Adds a field to an embed map if the value is available.

  ## Parameters
  - embed: The embed map to update
  - name: The name of the field
  - value: The value of the field (or nil)
  - inline: Whether the field should be displayed inline

  ## Returns
  The updated embed map with the field added if value is not nil
  """
  def add_field_if_available(embed, name, value, inline \\ true)
  def add_field_if_available(embed, _name, nil, _inline), do: embed
  def add_field_if_available(embed, _name, "", _inline), do: embed

  def add_field_if_available(embed, name, value, inline) do
    # Ensure the fields key exists
    embed = Map.put_new(embed, :fields, [])

    # Add the new field
    Map.update!(embed, :fields, fn fields ->
      fields ++ [%{name: name, value: to_string(value), inline: inline}]
    end)
  end

  @doc """
  Creates a basic embed structure.

  ## Parameters
  - title: The title of the embed
  - description: The description of the embed
  - color: The color of the embed (atom, integer, or hex string)

  ## Returns
  - A basic embed structure
  """
  def create_basic_embed(title, description, color) do
    %{
      title: title,
      description: description,
      color: convert_color(color),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      fields: []
    }
  end

  @doc """
  Adds an author to an embed.

  ## Parameters
  - embed: The embed to update
  - name: The author's name
  - icon_url: Optional URL for the author's icon
  - url: Optional URL for the author's name to link to

  ## Returns
  - The updated embed
  """
  def add_author(embed, name, icon_url \\ nil, url \\ nil) do
    author = %{name: name}
    author = if icon_url, do: Map.put(author, :icon_url, icon_url), else: author
    author = if url, do: Map.put(author, :url, url), else: author

    Map.put(embed, :author, author)
  end

  @doc """
  Adds a thumbnail to an embed.

  ## Parameters
  - embed: The embed to update
  - url: The URL of the thumbnail image

  ## Returns
  - The updated embed
  """
  def add_thumbnail(embed, url) when is_binary(url) do
    Map.put(embed, :thumbnail, %{url: url})
  end

  def add_thumbnail(embed, _), do: embed

  @doc """
  Adds a footer to an embed.

  ## Parameters
  - embed: The embed to update
  - text: The footer text
  - icon_url: Optional URL for the footer icon

  ## Returns
  - The updated embed
  """
  def add_footer(embed, text, icon_url \\ nil) do
    footer = %{text: text}
    footer = if icon_url, do: Map.put(footer, :icon_url, icon_url), else: footer

    Map.put(embed, :footer, footer)
  end
end
