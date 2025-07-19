defmodule WandererNotifier.Domains.Notifications.Formatters.Character do
  @moduledoc """
  Character notification formatting utilities for Discord notifications.
  Provides rich formatting for character tracking events.
  """

  alias WandererNotifier.Domains.CharacterTracking.Character
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.Notifications.Formatters.Base

  @doc """
  Creates a standard formatted new tracked character notification from a Character struct.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A Discord-formatted embed for the notification
  """
  def format_character_notification(%Character{} = character) do
    Base.with_error_handling(__MODULE__, "format character notification", character, fn ->
      fields = build_character_fields(character)

      Base.build_notification(%{
        type: :character_notification,
        title: "New Character Tracked",
        description: "A new character has been added to the tracking list.",
        color: :info,
        thumbnail: Base.build_thumbnail(Base.character_portrait_url(character.character_id, 128)),
        fields: fields
      })
    end)
  end

  defp build_character_fields(character) do
    character_field =
      Base.build_field(
        "Character",
        Base.create_character_link(character.name, character.character_id),
        true
      )

    [character_field | build_corporation_field(character)]
  end

  defp build_corporation_field(character) do
    case Character.has_corporation?(character) do
      true ->
        corporation_link =
          Base.create_corporation_link(
            character.corporation_ticker,
            character.corporation_id
          )

        [Base.build_field("Corporation", corporation_link, true)]

      false ->
        AppLogger.processor_warn(
          "[CharacterFormatter] No corporation data available for inclusion"
        )

        []
    end
  end
end
