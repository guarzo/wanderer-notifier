defmodule WandererNotifier.Domains.Notifications.Utils.FormatterUtils do
  @moduledoc """
  Shared formatting utilities for notification formatters.

  Contains common functions used across killmail, character, and system formatters.
  """

  alias WandererNotifier.Shared.Utils.TimeUtils

  # ══════════════════════════════════════════════════════════════════════════════
  # ISK Formatting
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats ISK values with appropriate units (B for billions, M for millions, K for thousands).
  """
  def format_isk(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 ->
        "#{Float.round(value / 1_000_000_000, 1)}B"

      value >= 1_000_000 ->
        "#{Float.round(value / 1_000_000, 1)}M"

      value >= 1_000 ->
        "#{Float.round(value / 1_000, 1)}K"

      true ->
        "#{Float.round(value, 0)}"
    end
  end

  def format_isk(_), do: "0"

  @doc """
  Formats ISK values with commas for readability.
  """
  def format_isk_with_commas(value) when is_number(value) do
    value
    |> Float.round(0)
    |> trunc()
    |> Integer.to_string()
    |> add_commas()
  end

  def format_isk_with_commas(_), do: "0"

  defp add_commas(string) do
    string
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Text Formatting
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Truncates text to a maximum length with ellipsis.
  """
  def truncate_text(text, max_length) when is_binary(text) and is_integer(max_length) do
    if String.length(text) <= max_length do
      text
    else
      text
      |> String.slice(0, max_length - 3)
      |> Kernel.<>("...")
    end
  end

  def truncate_text(text, _max_length), do: to_string(text)

  @doc """
  Capitalizes the first letter of a string.
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

  # ══════════════════════════════════════════════════════════════════════════════
  # Timestamp Formatting
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats a timestamp with EVE context and relative time.
  """
  def format_timestamp_with_context(datetime) when is_struct(datetime, DateTime) do
    relative_time = TimeUtils.format_relative_time(datetime)

    # For very recent kills (< 1 hour), show relative time
    # For older kills, show absolute time with EVE context
    cond do
      relative_time == "just now" ->
        relative_time

      String.contains?(relative_time, "seconds ago") or
          String.contains?(relative_time, "minutes ago") ->
        relative_time

      String.contains?(relative_time, "hour") ->
        "#{relative_time} (#{format_eve_time(datetime)})"

      true ->
        format_absolute_eve_time(datetime)
    end
  end

  def format_timestamp_with_context(timestamp) when is_binary(timestamp) do
    case TimeUtils.parse_iso8601(timestamp) do
      {:ok, datetime} -> format_timestamp_with_context(datetime)
      {:error, _reason} -> "Recently"
    end
  end

  def format_timestamp_with_context(_), do: "Recently"

  @doc """
  Formats time with EVE context for recent events.
  """
  def format_eve_time(datetime) when is_struct(datetime, DateTime) do
    "#{Calendar.strftime(datetime, "%H:%M")} EVE"
  end

  def format_eve_time(_), do: "Unknown EVE"

  @doc """
  Formats absolute time for older events.
  """
  def format_absolute_eve_time(datetime) when is_struct(datetime, DateTime) do
    now = TimeUtils.now()

    if same_date?(datetime, now) do
      "#{format_12_hour_time(datetime)} EVE today"
    else
      "#{Calendar.strftime(datetime, "%b %d")} at #{format_12_hour_time(datetime)} EVE"
    end
  end

  def format_absolute_eve_time(_), do: "Unknown EVE"

  # ══════════════════════════════════════════════════════════════════════════════
  # Color Formatting
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Gets Discord color code based on ISK value.
  """
  def get_isk_color(value) when is_number(value) do
    cond do
      # Red for very high value
      value >= 5_000_000_000 -> 0xFF0000
      # Orange for high value
      value >= 1_000_000_000 -> 0xFF6600
      # Yellow for medium value
      value >= 100_000_000 -> 0xFFFF00
      # Green for low value
      value >= 10_000_000 -> 0x00FF00
      # Gray for very low value
      true -> 0x808080
    end
  end

  def get_isk_color(_), do: 0x808080

  @doc """
  Gets Discord color code for system notifications.
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

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  # Check if two DateTime structs are on the same calendar day
  defp same_date?(%DateTime{} = dt1, %DateTime{} = dt2) do
    Calendar.strftime(dt1, "%Y-%m-%d") == Calendar.strftime(dt2, "%Y-%m-%d")
  end

  # Format time in 12-hour format
  defp format_12_hour_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
    # Remove leading zero from hour
    |> String.replace(~r/^0/, "")
  end
end
