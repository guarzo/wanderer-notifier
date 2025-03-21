defmodule WandererNotifier.Notifiers.Formatter do
  @moduledoc """
  Formatter for notification data, extracting and formatting information from API
  responses and notifications.
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
      get_in(character_data, ["character", "eve_id"]) ->
        get_in(character_data, ["character", "eve_id"])

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
        statics
        |> Enum.map(fn
          %{"name" => name, "destination" => %{"short_name" => short_name}} ->
            "#{name} (#{short_name})"
        end)
        |> Enum.join(", ")

      # Simple string list
      Enum.all?(statics, &is_binary/1) ->
        Enum.join(statics, ", ")

      true ->
        ""
    end
  end

  def format_statics_list(_), do: ""
end
