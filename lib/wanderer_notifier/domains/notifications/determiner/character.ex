defmodule WandererNotifier.Domains.Notifications.Determiner.Character do
  @moduledoc """
  Determines whether character notifications should be sent.
  Handles all character-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Deduplication
  alias WandererNotifier.Domains.CharacterTracking.Character

  @doc """
  Determines if a notification should be sent for a character.

  ## Parameters
    - character_id: The ID of the character to check
    - character_data: The character data to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(character_id, _character_data) do
    if Config.character_notifications_enabled?() do
      case Deduplication.check(:character, character_id) do
        {:ok, :new} -> true
        {:ok, :duplicate} -> false
        {:error, _reason} -> true
      end
    else
      false
    end
  end

  @doc """
  Checks if a character is being tracked.

  ## Parameters
    - character_id: The ID of the character to check

  ## Returns
    - true if the character is tracked
    - false otherwise
  """
  def tracked_character?(character_id) when is_integer(character_id) do
    character_id_str = Integer.to_string(character_id)
    tracked_character?(character_id_str)
  end

  def tracked_character?(character_id_str) when is_binary(character_id_str) do
    case Character.is_tracked?(character_id_str) do
      {:ok, tracked} -> tracked
      _ -> false
    end
  end

  def tracked_character?(_), do: false

  @doc """
  Checks if a character's data has changed from what's in cache.

  ## Parameters
    - character_id: The ID of the character to check
    - character_data: The new character data to compare against cache

  ## Returns
    - true if the character data has changed
    - false otherwise
  """
  def character_changed?(character_id, new_data)
      when is_binary(character_id) or is_integer(character_id) do
    case Cache.get_character(character_id) do
      {:ok, old_data} when old_data != nil ->
        old_data != new_data

      {:error, :not_found} ->
        true

      _ ->
        true
    end
  end

  def character_changed?(_, _), do: false
end
