defmodule WandererNotifier.Domains.Notifications.Formatters.CharacterFormatter do
  @moduledoc """
  Formats character notifications for Discord.

  Handles character tracking notifications including character details,
  corporation and alliance information.
  """

  alias WandererNotifier.Domains.Tracking.Entities.Character
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationUtils, as: Utils
  alias WandererNotifier.Domains.Notifications.Utils.FormatterUtils
  require Logger

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats a character notification for Discord.
  """
  def format(%Character{} = character, opts \\ []) do
    format_character_notification(character, opts)
  end

  @doc """
  Formats a character embed for Discord.
  """
  def format_embed(%Character{} = character, opts \\ []) do
    format_character_notification(character, opts)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Main Formatting Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp format_character_notification(%Character{} = character, _opts) do
    # Convert character_id to integer for portrait URL
    character_id_int = normalize_character_id(character.character_id)

    %{
      type: :character_notification,
      title: build_character_title(character),
      description: build_character_description(character),
      color: FormatterUtils.get_character_color(:added),
      url: character_id_int && "https://zkillboard.com/character/#{character_id_int}/",
      thumbnail:
        character_id_int &&
          Utils.character_portrait_url(character_id_int) |> Utils.build_thumbnail(),
      fields: build_character_fields(character),
      footer: Utils.build_footer("Character ID: #{character.character_id}")
    }
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Title and Description Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_character_title(%Character{} = character) do
    cond do
      character.tracked == true -> "New Character Tracked: #{character.name}"
      character.tracked == false -> "Character Removed: #{character.name}"
      true -> "Character Update: #{character.name}"
    end
  end

  defp build_character_description(%Character{} = character) do
    cond do
      character.tracked == true ->
        "A new character has been added to tracking."

      character.tracked == false ->
        "A character has been removed from tracking."

      true ->
        "Character tracking information has been updated."
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Field Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_character_fields(%Character{} = character) do
    []
    |> add_character_field(character)
    |> add_corporation_field(character)
    |> add_alliance_field(character)
    |> add_status_field(character)
    |> Enum.reverse()
  end

  defp add_character_field(fields, %Character{} = character) do
    character_id_int = normalize_character_id(character.character_id)
    char_link = Utils.create_character_link(character.name, character_id_int)
    [Utils.build_field("Character", char_link, true) | fields]
  end

  defp add_corporation_field(fields, %Character{corporation_id: nil}), do: fields

  defp add_corporation_field(fields, %Character{} = character) do
    corp_name = get_corporation_name(character)
    corp_link = Utils.create_corporation_link(corp_name, character.corporation_id)
    [Utils.build_field("Corporation", corp_link, true) | fields]
  end

  defp add_alliance_field(fields, %Character{alliance_id: nil}), do: fields

  defp add_alliance_field(fields, %Character{} = character) do
    alliance_name = get_alliance_name(character)
    alliance_link = Utils.create_alliance_link(alliance_name, character.alliance_id)
    [Utils.build_field("Alliance", alliance_link, true) | fields]
  end

  # Location field not available in current Character struct - removed

  defp add_status_field(fields, %Character{} = character) do
    status =
      cond do
        character.tracked == true -> "🟢 Tracked"
        character.tracked == false -> "🔴 Not Tracked"
        true -> "🟡 Unknown"
      end

    [Utils.build_field("Status", status, true) | fields]
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp normalize_character_id(id) when is_integer(id), do: id

  defp normalize_character_id(id) when is_binary(id) do
    try do
      String.to_integer(id)
    rescue
      ArgumentError ->
        Logger.warning("Failed to convert character ID to integer", invalid_id: id)
        nil
    end
  end

  defp normalize_character_id(_), do: nil

  # Helper functions to get corporation and alliance names from character data
  defp get_corporation_name(%Character{} = character) do
    # For character notifications, we want to use ticker as the primary name since
    # we don't have full corp names in the character tracking data
    character.corporation_ticker || "Unknown Corporation"
  end

  defp get_alliance_name(%Character{} = character) do
    # For character notifications, we want to use ticker as the primary name since
    # we don't have full alliance names in the character tracking data
    character.alliance_ticker || "Unknown Alliance"
  end

  # System name helper removed - not available in Character struct
end
