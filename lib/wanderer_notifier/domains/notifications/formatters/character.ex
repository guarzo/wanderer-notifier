defmodule WandererNotifier.Domains.Notifications.Formatters.Character do
  @moduledoc """
  Character notification formatting utilities for Discord notifications.
  Provides rich formatting for character tracking events.
  """

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.Notifications.Formatters.Base

  @doc """
  Creates a standard formatted new tracked character notification from a Character struct.

  ## Parameters
    - character: The Character struct

  ## Returns
    - A Discord-formatted embed for the notification
  """
  def format_character_notification(character) do
    # Accept any struct that has the required fields
    case character do
      %{character_id: _, name: _} ->
        fields = build_character_fields(character)

        Base.build_notification(%{
          type: :character_notification,
          title: "New Character Tracked",
          description: "A new character has been added to the tracking list.",
          color: :info,
          thumbnail:
            Base.build_thumbnail(Base.character_portrait_url(character.character_id, 128)),
          fields: fields
        })

      _ ->
        raise ArgumentError, "Invalid character struct: #{inspect(character)}"
    end
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
    # Check if character has corporation data
    has_corporation =
      case character do
        %{corporation_id: corp_id} when is_integer(corp_id) and corp_id > 0 -> true
        _ -> false
      end

    case has_corporation do
      true ->
        corporation_link =
          Base.create_corporation_link(
            Map.get(character, :corporation_ticker, ""),
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
