defmodule WandererNotifier.Notifications.Formatters.Base do
  @moduledoc """
  Base formatting utilities for notifications.
  Provides common formatting functions used across different notification types.
  """

  @doc """
  Extracts a character ID from different data formats.
  """
  def extract_character_id(character_data) when is_map(character_data) do
    cond do
      # Notification format
      Map.has_key?(character_data, "character_id") ->
        character_data["character_id"]

      # Standard API format
      get_in(character_data, ["character", "character_id"]) ->
        get_in(character_data, ["character", "character_id"])

      # No character ID found
      true ->
        nil
    end
  end

  @doc """
  Extracts a character name from different data formats.
  """
  def extract_character_name(character_data) when is_map(character_data) do
    cond do
      # Notification format
      Map.has_key?(character_data, "character_name") ->
        character_data["character_name"]

      # Standard API format
      get_in(character_data, ["character", "name"]) ->
        get_in(character_data, ["character", "name"])

      # No character name found
      true ->
        "Unknown Character"
    end
  end

  @doc """
  Extracts a corporation ID from different data formats.
  """
  def extract_corporation_id(character_data) when is_map(character_data) do
    cond do
      # Notification format
      Map.has_key?(character_data, "corporation_id") ->
        character_data["corporation_id"]

      # Standard API format
      get_in(character_data, ["character", "corporation_id"]) ->
        get_in(character_data, ["character", "corporation_id"])

      # No corporation ID found
      true ->
        nil
    end
  end

  @doc """
  Extracts a corporation name from different data formats.
  """
  def extract_corporation_name(character_data) when is_map(character_data) do
    cond do
      # Notification format
      Map.has_key?(character_data, "corporation_name") ->
        character_data["corporation_name"]

      # Standard API format with ticker
      get_in(character_data, ["character", "corporation_ticker"]) ->
        get_in(character_data, ["character", "corporation_ticker"])

      # No corporation name found
      true ->
        "Unknown Corporation"
    end
  end

  @doc """
  Formats a list of statics for display.
  """
  def format_statics_list(statics) when is_binary(statics) do
    # Already formatted string
    statics
  end

  def format_statics_list(statics) when is_list(statics) do
    cond do
      # List with destination info
      Enum.all?(statics, &(is_map(&1) and Map.has_key?(&1, "destination"))) ->
        Enum.map_join(statics, ", ", fn
          %{"name" => name, "destination" => %{"short_name" => short_name}} ->
            "#{name} (#{short_name})"
        end)

      # Simple string list
      Enum.all?(statics, &is_binary/1) ->
        Enum.join(statics, ", ")

      true ->
        ""
    end
  end

  def format_statics_list(_), do: ""

  @doc """
  Formats a security status value with color coding.
  """
  def format_security_status(security_status) when is_number(security_status) do
    # Round to 1 decimal place
    rounded = Float.round(security_status, 1)

    # Format with color based on value
    cond do
      rounded >= 0.5 -> "#{rounded} (High)"
      rounded > 0.0 -> "#{rounded} (Low)"
      true -> "#{rounded} (Null)"
    end
  end

  def format_security_status(security_status) when is_binary(security_status) do
    # Convert string to float and then format
    case Float.parse(security_status) do
      {value, _} -> format_security_status(value)
      :error -> "Unknown"
    end
  end

  @doc """
  Formats ISK value in a compact way.
  """
  def format_compact_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B ISK"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M ISK"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K ISK"
      true -> "#{Float.round(value, 1)} ISK"
    end
  end

  def format_compact_isk_value(_), do: "Unknown Value"
end
