defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationUtils do
  @moduledoc """
  Consolidated utilities for notification formatting.
  Single source of truth for all formatting helpers.
  """

  alias WandererNotifier.Shared.Utils.FormattingUtils
  alias WandererNotifier.Shared.Config

  # ═══════════════════════════════════════════════════════════════════════════════
  # URL Generation
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Generate zKillboard URL for a kill"
  def zkillboard_url(kill_id) when is_binary(kill_id) do
    "https://zkillboard.com/kill/#{kill_id}/"
  end

  def zkillboard_url(kill_id) when is_integer(kill_id) do
    "https://zkillboard.com/kill/#{kill_id}/"
  end

  def zkillboard_url(_), do: nil

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
  def format_isk(value), do: FormattingUtils.format_isk(value, precision: 2)

  @doc "Format number with thousand separators"
  def format_number(value), do: FormattingUtils.format_number(value)

  @doc "Format percentage"
  def format_percentage(value), do: FormattingUtils.format_percentage(value)

  # ═══════════════════════════════════════════════════════════════════════════════
  # Color Management
  # ═══════════════════════════════════════════════════════════════════════════════

  @colors %{
    default: 0x3498DB,
    info: 0x3498DB,
    success: 0x5CB85C,
    warning: 0xE28A0D,
    error: 0xD9534F,
    # Purple color for wormholes
    wormhole: 0x9D4EDD,
    # Green for high-sec
    highsec: 0x00FF00,
    # Yellow for low-sec
    lowsec: 0xFFFF00,
    # Red for null-sec
    nullsec: 0xFF0000,
    kill: 0xD9534F,
    character: 0x3498DB,
    system: 0x428BCA
  }

  @doc "Get color value for a given type"
  def get_color(type) when is_atom(type) do
    Map.get(@colors, type, @colors.default)
  end

  def get_color(type) when is_binary(type) do
    type
    |> String.downcase()
    |> string_to_atom()
    |> get_color_for_atom()
  end

  def get_color(_), do: @colors.default

  @string_to_atom_map %{
    "default" => :default,
    "info" => :info,
    "success" => :success,
    "warning" => :warning,
    "error" => :error,
    "wormhole" => :wormhole,
    "highsec" => :highsec,
    "lowsec" => :lowsec,
    "nullsec" => :nullsec,
    "kill" => :kill,
    "character" => :character,
    "system" => :system
  }

  defp string_to_atom(type_string) do
    Map.get(@string_to_atom_map, type_string, :default)
  end

  defp get_color_for_atom(type_atom) do
    Map.get(@colors, type_atom, @colors.default)
  end

  @doc "Determine color based on security status"
  def security_color(sec_status) when is_number(sec_status) do
    cond do
      sec_status >= 0.5 -> :highsec
      sec_status > 0.0 -> :lowsec
      sec_status == 0.0 -> :nullsec
      true -> :wormhole
    end
  end

  def security_color("High Sec"), do: :highsec
  def security_color("Low Sec"), do: :lowsec
  def security_color("Null Sec"), do: :nullsec
  def security_color("Wormhole"), do: :wormhole
  def security_color("W-Space"), do: :wormhole
  def security_color(_), do: :default

  # ═══════════════════════════════════════════════════════════════════════════════
  # Link Creation
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Create a markdown link"
  def create_link(text, url) when is_binary(text) and is_binary(url) do
    "[#{text}](#{url})"
  end

  def create_link(text, _), do: text || ""

  @doc "Create character link with zKillboard instead of EVE Who"
  def create_character_link(name, character_id) when is_integer(character_id) do
    url = "https://zkillboard.com/character/#{character_id}/"
    create_link(name || "Unknown", url)
  end

  def create_character_link(name, character_id) when is_binary(character_id) do
    url = "https://zkillboard.com/character/#{character_id}/"
    create_link(name || "Unknown", url)
  end

  def create_character_link(name, _), do: name || "Unknown"

  @doc "Create system link with Dotlan"
  def create_system_link(name, _system_id) when is_binary(name) do
    create_link(name, dotlan_system_url(name))
  end

  def create_system_link(name, _), do: name || "Unknown"

  @doc "Create corporation link with zKillboard"
  def create_corporation_link(name, corporation_id) when is_integer(corporation_id) do
    url = "https://zkillboard.com/corporation/#{corporation_id}/"
    create_link(name || "Unknown Corporation", url)
  end

  def create_corporation_link(name, _), do: name || "Unknown Corporation"

  @doc "Create alliance link with zKillboard"
  def create_alliance_link(name, alliance_id) when is_integer(alliance_id) do
    url = "https://zkillboard.com/alliance/#{alliance_id}/"
    create_link(name || "Unknown Alliance", url)
  end

  def create_alliance_link(name, _), do: name || "Unknown Alliance"

  # ═══════════════════════════════════════════════════════════════════════════════
  # Icon Management
  # ═══════════════════════════════════════════════════════════════════════════════

  @system_icons %{
    # Wormhole sun
    wormhole: "https://images.evetech.net/types/45041/icon?size=64",
    # K-type main sequence star (high-sec)
    highsec: "https://images.evetech.net/types/45038/icon?size=64",
    # G-type main sequence star (low-sec)
    lowsec: "https://images.evetech.net/types/45039/icon?size=64",
    # M-type red giant star (null-sec)
    nullsec: "https://images.evetech.net/types/45040/icon?size=64"
  }

  @doc "Get icon URL for system type"
  def get_system_icon(type) when is_atom(type) do
    Map.get(@system_icons, type, @system_icons.wormhole)
  end

  def get_system_icon("High Sec"), do: @system_icons.highsec
  def get_system_icon("Low Sec"), do: @system_icons.lowsec
  def get_system_icon("Null Sec"), do: @system_icons.nullsec
  def get_system_icon("Wormhole"), do: @system_icons.wormhole
  def get_system_icon("W-Space"), do: @system_icons.wormhole
  def get_system_icon(_), do: @system_icons.wormhole

  # ═══════════════════════════════════════════════════════════════════════════════
  # Rally Mentions
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc "Build rally group mentions from configured IDs"
  def rally_mentions do
    Enum.map_join(Config.discord_rally_group_ids(), " ", fn id -> "<@&#{id}>" end)
  end

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
