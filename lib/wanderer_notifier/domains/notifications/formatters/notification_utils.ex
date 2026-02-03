defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationUtils do
  @moduledoc """
  Utilities for notification formatting.

  Provides helpers for:
  - URL generation (zKillboard, EVE images, Dotlan, EVE Who)
  - Value formatting (ISK, numbers, percentages)
  - Color management (ISK-based, security-based, system/character notifications)
  - Link creation (markdown links for characters, systems, corporations, alliances)
  - Icon management (system type icons)
  - Field building helpers for Discord embeds
  - Text utilities (truncation, capitalization)
  - Timestamp formatting with EVE context
  """

  alias WandererNotifier.Shared.Utils.FormattingUtils
  alias WandererNotifier.Shared.Utils.TimeUtils
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

  # ═══════════════════════════════════════════════════════════════════════════════
  # ISK-Based Color Management
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Gets Discord color code based on ISK value.

  Returns color codes based on value thresholds:
  - >= 5B ISK: Red (0xFF0000) - Very high value
  - >= 1B ISK: Orange (0xFF6600) - High value
  - >= 100M ISK: Yellow (0xFFFF00) - Medium value
  - >= 10M ISK: Green (0x00FF00) - Low value
  - < 10M ISK: Gray (0x808080) - Very low value
  """
  # Red for very high value (>= 5B)
  def get_isk_color(value) when is_number(value) and value >= 5_000_000_000, do: 0xFF0000
  # Orange for high value (>= 1B)
  def get_isk_color(value) when is_number(value) and value >= 1_000_000_000, do: 0xFF6600
  # Yellow for medium value (>= 100M)
  def get_isk_color(value) when is_number(value) and value >= 100_000_000, do: 0xFFFF00
  # Green for low value (>= 10M)
  def get_isk_color(value) when is_number(value) and value >= 10_000_000, do: 0x00FF00
  # Gray for very low value (< 10M)
  def get_isk_color(value) when is_number(value), do: 0x808080
  # Gray for non-numbers
  def get_isk_color(_), do: 0x808080

  @doc """
  Gets Discord color code for system notifications.

  Returns color codes for system events:
  - :added - Green (0x00FF00)
  - :removed - Red (0xFF0000)
  - :updated - Yellow (0xFFFF00)
  - Other - Gray (0x808080)
  """
  # Green
  def get_system_color(:added), do: 0x00FF00
  # Red
  def get_system_color(:removed), do: 0xFF0000
  # Yellow
  def get_system_color(:updated), do: 0xFFFF00
  # Gray
  def get_system_color(_), do: 0x808080

  @doc """
  Gets Discord color code for character notifications.

  Returns color codes for character events:
  - :online - Green (0x00FF00)
  - :offline - Red (0xFF0000)
  - :added - Cyan (0x00FFFF)
  - :removed - Orange (0xFF6600)
  - Other - Gray (0x808080)
  """
  # Green
  def get_character_color(:online), do: 0x00FF00
  # Red
  def get_character_color(:offline), do: 0xFF0000
  # Cyan
  def get_character_color(:added), do: 0x00FFFF
  # Orange
  def get_character_color(:removed), do: 0xFF6600
  # Gray
  def get_character_color(_), do: 0x808080

  # ═══════════════════════════════════════════════════════════════════════════════
  # Text Formatting Utilities
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Truncates text to a maximum length with ellipsis.

  ## Examples
      iex> truncate_text("Hello World", 8)
      "Hello..."

      iex> truncate_text("Hi", 10)
      "Hi"
  """
  def truncate_text(text, max_length) when is_binary(text) and is_integer(max_length) do
    cond do
      String.length(text) <= max_length ->
        text

      max_length <= 3 ->
        String.slice(text, 0, max_length)

      true ->
        text
        |> String.slice(0, max_length - 3)
        |> Kernel.<>("...")
    end
  end

  def truncate_text(text, _max_length), do: to_string(text)

  @doc """
  Capitalizes the first letter of a string.

  ## Examples
      iex> capitalize_first("hello")
      "Hello"

      iex> capitalize_first("HELLO")
      "HELLO"
  """
  def capitalize_first(text) when is_binary(text) do
    case String.length(text) do
      0 ->
        text

      1 ->
        String.upcase(text)

      _ ->
        text
        |> String.at(0)
        |> String.upcase()
        |> Kernel.<>(String.slice(text, 1..-1//1))
    end
  end

  def capitalize_first(text), do: to_string(text)

  # ═══════════════════════════════════════════════════════════════════════════════
  # Timestamp Formatting with EVE Context
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats a timestamp with EVE context and relative time.

  For recent events (< 1 hour), shows relative time like "5 minutes ago".
  For older events, shows absolute time with EVE context.
  """
  def format_timestamp_with_context(datetime) when is_struct(datetime, DateTime) do
    relative_time = TimeUtils.format_relative_time(datetime)
    format_relative_with_context(relative_time, datetime)
  end

  def format_timestamp_with_context(timestamp) when is_binary(timestamp) do
    case TimeUtils.parse_iso8601(timestamp) do
      {:ok, datetime} -> format_timestamp_with_context(datetime)
      {:error, _reason} -> "Recently"
    end
  end

  def format_timestamp_with_context(_), do: "Recently"

  # Pattern-matched helper for relative time formatting
  defp format_relative_with_context("just now", _datetime), do: "just now"

  defp format_relative_with_context(relative_time, datetime) do
    cond do
      String.contains?(relative_time, "seconds ago") ->
        relative_time

      String.contains?(relative_time, "minutes ago") ->
        relative_time

      String.contains?(relative_time, "hour") ->
        "#{relative_time} (#{format_eve_time(datetime)})"

      true ->
        format_absolute_eve_time(datetime)
    end
  end

  @doc """
  Formats time with EVE context for recent events.

  ## Examples
      iex> format_eve_time(~U[2024-01-15 14:30:00Z])
      "14:30 EVE"
  """
  def format_eve_time(datetime) when is_struct(datetime, DateTime) do
    "#{Calendar.strftime(datetime, "%H:%M")} EVE"
  end

  def format_eve_time(_), do: "Unknown EVE"

  @doc """
  Formats absolute time for older events.

  Shows "HH:MM AM/PM EVE today" for same-day events,
  or "Mon DD at HH:MM AM/PM EVE" for older events.
  """
  def format_absolute_eve_time(datetime) when is_struct(datetime, DateTime) do
    now = TimeUtils.now()

    case same_date?(datetime, now) do
      true -> "#{format_12_hour_time(datetime)} EVE today"
      false -> "#{Calendar.strftime(datetime, "%b %d")} at #{format_12_hour_time(datetime)} EVE"
    end
  end

  def format_absolute_eve_time(_), do: "Unknown EVE"

  @doc """
  Formats ISK values with commas for readability, including the ISK suffix.

  ## Examples
      iex> format_isk_with_commas(2_500_000_000)
      "2,500,000,000 ISK"
  """
  def format_isk_with_commas(value), do: FormattingUtils.format_isk_full(value)

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════════

  # Check if two DateTime structs are on the same calendar day
  defp same_date?(%DateTime{} = dt1, %DateTime{} = dt2) do
    DateTime.to_date(dt1) == DateTime.to_date(dt2)
  end

  # Format time in 12-hour format
  defp format_12_hour_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
