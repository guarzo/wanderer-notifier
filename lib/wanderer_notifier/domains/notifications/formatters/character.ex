defmodule WandererNotifier.Domains.Notifications.Formatters.Character do
  @moduledoc """
  Character notification formatting utilities.
  Now delegates to the unified formatter for consistency.
  """

  alias WandererNotifier.Domains.Tracking.Entities.Character
  alias WandererNotifier.Domains.Notifications.Formatters.Unified

  @doc """
  Format a character notification using the unified formatter.
  Maintains backward compatibility for existing callers.
  """
  def format_character_notification(%Character{} = character) do
    Unified.format_notification(character)
  end

  @doc """
  Legacy function for getting character portrait URL.
  """
  defdelegate get_character_portrait_url(character_id, size \\ 128),
    to: WandererNotifier.Domains.Notifications.Formatters.Utilities,
    as: :character_portrait_url
end
