defmodule WandererNotifier.Map.MapCharacter do
  @moduledoc """
  Alias module for backward compatibility.
  All functionality is provided by WandererNotifier.Domains.CharacterTracking.Character
  """

  # Import all functions from the actual module
  defdelegate __struct__, to: WandererNotifier.Domains.CharacterTracking.Character
  defdelegate __struct__(fields), to: WandererNotifier.Domains.CharacterTracking.Character

  # Re-export the struct type
  @type t :: WandererNotifier.Domains.CharacterTracking.Character.t()

  # Delegate module functions
  defdelegate new(attrs), to: WandererNotifier.Domains.CharacterTracking.Character
  defdelegate new_safe(attrs), to: WandererNotifier.Domains.CharacterTracking.Character

  defdelegate has_corporation?(character),
    to: WandererNotifier.Domains.CharacterTracking.Character

  defdelegate is_tracked?(character_id), to: WandererNotifier.Domains.CharacterTracking.Character

  defdelegate get_character_by_name(character_name),
    to: WandererNotifier.Domains.CharacterTracking.Character
end
