defmodule WandererNotifier.Domains.Notifications.Formatters.Utilities do
  @moduledoc """
  Shared utilities for notification formatting.
  Centralizes common formatting functions to eliminate duplication.
  """

  alias WandererNotifier.Shared.Utils.ErrorHandler

  # ═══════════════════════════════════════════════════════════════════════════════
  # URL Generation
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Generate zKillboard URL for a kill"
  def zkillboard_url(kill_id) when is_binary(kill_id) do
    "https://zkillboard.com/kill/#{kill_id}/"
  end

  def zkillboard_url(kill_id), do: zkillboard_url(to_string(kill_id))

  @doc "Generate character portrait URL"
  def character_portrait_url(character_id, size \\ 128)

  def character_portrait_url(character_id, size) when is_integer(character_id) do
    "https://images.evetech.net/characters/#{character_id}/portrait?size=#{size}"
  end

  def character_portrait_url(_, _), do: nil

  @doc "Generate corporation logo URL"
  def corporation_logo_url(corp_id, size \\ 128)

  def corporation_logo_url(corp_id, size) when is_integer(corp_id) do
    "https://images.evetech.net/corporations/#{corp_id}/logo?size=#{size}"
  end

  def corporation_logo_url(_, _), do: nil

  @doc "Generate alliance logo URL"
  def alliance_logo_url(alliance_id, size \\ 128)

  def alliance_logo_url(alliance_id, size) when is_integer(alliance_id) do
    "https://images.evetech.net/alliances/#{alliance_id}/logo?size=#{size}"
  end

  def alliance_logo_url(_, _), do: nil

  @doc "Generate ship type render URL"
  def ship_render_url(type_id, size \\ 128)

  def ship_render_url(type_id, size) when is_integer(type_id) do
    "https://images.evetech.net/types/#{type_id}/render?size=#{size}"
  end

  def ship_render_url(_, _), do: nil

  @doc "Generate EVE Who URL for character"
  def evewho_url(character_id) when is_integer(character_id) do
    "https://evewho.com/character/#{character_id}"
  end

  def evewho_url(_), do: nil

  @doc "Generate Dotlan URL for system"
  def dotlan_system_url(system_name) when is_binary(system_name) do
    sanitized = String.replace(system_name, " ", "_")
    "https://evemaps.dotlan.net/system/#{sanitized}"
  end

  def dotlan_system_url(_), do: nil

  @doc "Generate Dotlan URL for region"
  def dotlan_region_url(region_name) when is_binary(region_name) do
    sanitized = String.replace(region_name, " ", "_")
    "https://evemaps.dotlan.net/region/#{sanitized}"
  end

  def dotlan_region_url(_), do: nil

  # ═══════════════════════════════════════════════════════════════════════════════
  # Value Formatting
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Format ISK value with proper suffix"
  def format_isk(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 2)}B ISK"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 2)}M ISK"
      value >= 1_000 -> "#{Float.round(value / 1_000, 2)}K ISK"
      true -> "#{round(value)} ISK"
    end
  end

  def format_isk(_), do: "0 ISK"

  @doc "Format number with thousand separators"
  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  def format_number(number) when is_float(number) do
    number
    |> Float.round(2)
    |> Float.to_string()
  end

  def format_number(_), do: "0"

  @doc "Format percentage"
  def format_percentage(value) when is_number(value) do
    "#{Float.round(value * 100, 1)}%"
  end

  def format_percentage(_), do: "0%"

  # ═══════════════════════════════════════════════════════════════════════════════
  # Color Management
  # ═══════════════════════════════════════════════════════════════════════════════

  @colors %{
    default: 0x3498DB,
    info: 0x3498DB,
    success: 0x5CB85C,
    warning: 0xE28A0D,
    error: 0xD9534F,
    wormhole: 0x428BCA,
    highsec: 0x5CB85C,
    lowsec: 0xE28A0D,
    nullsec: 0xD9534F,
    kill: 0xD9534F,
    character: 0x3498DB,
    system: 0x428BCA
  }

  @doc "Get color value for a given type"
  def get_color(type) when is_atom(type) do
    Map.get(@colors, type, @colors.default)
  end

  def get_color(type) when is_binary(type) do
    ErrorHandler.safe_execute(
      fn ->
        type
        |> String.downcase()
        |> String.to_existing_atom()
        |> get_color()
      end,
      fallback: @colors.default,
      log_errors: false
    )
    |> case do
      {:ok, color} -> color
      {:error, _} -> @colors.default
    end
  end

  def get_color(_), do: @colors.default

  @doc "Determine color based on security status"
  def security_color(sec_status) when is_number(sec_status) do
    cond do
      sec_status >= 0.5 -> :highsec
      sec_status > 0.0 -> :lowsec
      true -> :nullsec
    end
  end

  def security_color("High Sec"), do: :highsec
  def security_color("Low Sec"), do: :lowsec
  def security_color("Null Sec"), do: :nullsec
  def security_color("Wormhole"), do: :wormhole
  def security_color(_), do: :default

  # ═══════════════════════════════════════════════════════════════════════════════
  # Link Creation
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Create a markdown link"
  def create_link(text, url) when is_binary(text) and is_binary(url) do
    "[#{text}](#{url})"
  end

  def create_link(text, _), do: text || ""

  @doc "Create character link with EVE Who"
  def create_character_link(name, character_id) when is_integer(character_id) do
    create_link(name || "Unknown", evewho_url(character_id))
  end

  def create_character_link(name, _), do: name || "Unknown"

  @doc "Create system link with Dotlan"
  def create_system_link(name, _system_id) when is_binary(name) do
    create_link(name, dotlan_system_url(name))
  end

  def create_system_link(name, _), do: name || "Unknown"

  # ═══════════════════════════════════════════════════════════════════════════════
  # Icon Management
  # ═══════════════════════════════════════════════════════════════════════════════

  @system_icons %{
    wormhole: "https://wiki.eveuniversity.org/images/e/e0/Systems.png",
    highsec: "https://wiki.eveuniversity.org/images/2/2b/Hisec.png",
    lowsec: "https://wiki.eveuniversity.org/images/1/17/Lowsec.png",
    nullsec: "https://wiki.eveuniversity.org/images/9/96/Nullsec.png"
  }

  @doc "Get icon URL for system type"
  def get_system_icon(type) when is_atom(type) do
    Map.get(@system_icons, type, @system_icons.wormhole)
  end

  def get_system_icon("High Sec"), do: @system_icons.highsec
  def get_system_icon("Low Sec"), do: @system_icons.lowsec
  def get_system_icon("Null Sec"), do: @system_icons.nullsec
  def get_system_icon("Wormhole"), do: @system_icons.wormhole
  def get_system_icon(_), do: @system_icons.wormhole

  # ═══════════════════════════════════════════════════════════════════════════════
  # Field Building
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Build a notification field"
  def build_field(name, value, inline \\ true) do
    %{
      name: to_string(name),
      value: to_string(value),
      inline: inline
    }
  end

  @doc "Build thumbnail structure"
  def build_thumbnail(url) when is_binary(url) do
    %{url: url}
  end

  def build_thumbnail(_), do: nil

  @doc "Build footer structure"
  def build_footer(text, icon_url \\ nil) do
    footer = %{text: to_string(text)}

    if icon_url do
      Map.put(footer, :icon_url, icon_url)
    else
      footer
    end
  end
end
