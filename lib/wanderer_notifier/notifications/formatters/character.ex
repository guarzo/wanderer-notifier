defmodule WandererNotifier.Notifications.Formatters.Character do
  @moduledoc """
  Character notification formatting utilities for Discord notifications.
  Provides rich formatting for character tracking events.
  """

  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @info_color 0x3498DB

  @doc """
  Creates a standard formatted new tracked character notification from a Character struct.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A Discord-formatted embed for the notification
  """
  def format_character_notification(%MapCharacter{} = character) do
    # Build notification structure
    %{
      type: :character_notification,
      title: "New Character Tracked",
      description: "A new character has been added to the tracking list.",
      color: @info_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        url: "https://imageserver.eveonline.com/Character/#{character.character_id}_128.jpg"
      },
      fields:
        [
          %{
            name: "Character",
            value:
              "[#{character.name}](https://zkillboard.com/character/#{character.character_id}/)",
            inline: true
          }
        ] ++
          if MapCharacter.has_corporation?(character) do
            corporation_link =
              "[#{character.corporation_ticker}](https://zkillboard.com/corporation/#{character.corporation_id}/)"

            [%{name: "Corporation", value: corporation_link, inline: true}]
          else
            AppLogger.processor_warn(
              "[CharacterFormatter] No corporation data available for inclusion"
            )

            []
          end
    }
  end
end
