defmodule WandererNotifier.Domains.Notifications.Formatters.CharacterUtils do
  @moduledoc """
  Utility functions for working with Character data.
  Provides helper functions for extracting and formatting character information.
  """

  alias WandererNotifier.Domains.CharacterTracking.Character

  @doc """
  Extracts a character ID from a Character struct.
  No fallbacks to maps supported.

  Returns the ID as a string.
  """
  @spec extract_character_id(Character.t()) :: String.t()
  def extract_character_id(%Character{} = character) do
    character.character_id
  end

  @doc """
  Extracts a character name from a Character struct.
  No fallbacks to maps supported.

  Returns the name as a string.
  """
  @spec extract_character_name(Character.t()) :: String.t()
  def extract_character_name(%Character{} = character) do
    character.name
  end

  @doc """
  Extracts a corporation name from a Character struct.
  No fallbacks to maps supported.

  Returns the corporation ticker as a string.
  """
  @spec extract_corporation_name(Character.t()) :: String.t()
  def extract_corporation_name(%Character{} = character) do
    character.corporation_ticker
  end

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
  @spec add_field_if_available(map(), String.t(), any(), boolean()) :: map()
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
end
