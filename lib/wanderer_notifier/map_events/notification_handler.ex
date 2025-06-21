defmodule WandererNotifier.MapEvents.NotificationHandler do
  @moduledoc """
  Handles notifications for map events using the existing notification system.

  This module bridges WebSocket events to the existing notification pipeline,
  enriching data as needed and delegating to the existing determiners and notifiers.
  """

  alias WandererNotifier.Map.MapCharacter
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifications.Determiner.System, as: SystemDeterminer
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  require Logger

  @doc """
  Notify when a system is added to the map
  """
  def notify_system_added(system) do
    Logger.debug("[MapEvents.System] Processing system notification",
      system_id: system["solar_system_id"],
      name: system["name"]
    )

    # Convert to MapSystem struct - let it handle all the data normalization
    system_struct = MapSystem.new(system)

    Logger.debug("[MapEvents.System] Created struct",
      solar_system_id: system_struct.solar_system_id,
      name: system_struct.name
    )

    # Use existing determiner to check if we should notify
    # SystemDeterminer expects (system_id, system_data)
    if SystemDeterminer.should_notify?(system_struct.solar_system_id, system_struct) do
      Logger.info("[MapEvents.System] Sending notification",
        system_id: system_struct.solar_system_id,
        name: system_struct.name
      )

      # Use existing Discord notifier
      DiscordNotifier.send_new_system_notification(system_struct)
    else
      Logger.debug("[MapEvents.System] Skipping notification (determiner said no)",
        system_id: system_struct.solar_system_id,
        name: system_struct.name
      )
    end
  end

  @doc """
  Notify when a system is removed from the map
  """
  def notify_system_removed(_system_id) do
    # System removal notifications not currently implemented in existing system
    # Could be added if needed
    :ok
  end

  @doc """
  Notify when a character is added to the map
  """
  def notify_character_added(character) do
    Logger.debug("[MapEvents.Character] Processing character notification",
      character_id: character["character_id"] || character["eve_id"],
      name: character["name"]
    )

    character
    |> build_map_character()
    |> handle_character_notification()
  end

  defp handle_character_notification({:ok, map_character}) do
    Logger.debug("[MapEvents.Character] Created struct",
      eve_id: map_character.eve_id,
      name: map_character.name
    )

    if CharacterDeterminer.should_notify?(map_character.eve_id, map_character) do
      Logger.info("[MapEvents.Character] Sending notification",
        character_id: map_character.eve_id,
        name: map_character.name
      )

      DiscordNotifier.send_new_tracked_character_notification(map_character)
    else
      Logger.debug("[MapEvents.Character] Skipping notification (determiner said no)",
        character_id: map_character.eve_id,
        name: map_character.name
      )
    end
  end

  defp handle_character_notification({:error, reason}) do
    Logger.error("[MapEvents.Character] Failed to build MapCharacter",
      reason: reason
    )
  end

  @doc """
  Notify when a character is removed from the map
  """
  def notify_character_removed(_character) do
    # Character removal notifications not currently implemented in existing system
    # Could be added if needed
    :ok
  end

  @doc """
  Notify when a character changes location
  """
  def notify_character_location_changed(_character) do
    # Location change notifications not currently implemented in existing system
    # The existing system only notifies on new character additions
    :ok
  end

  # Private functions

  defp build_map_character(character_data) do
    # Convert WebSocket character data to MapCharacter struct
    # The WebSocket should provide: character_id, name, corporation_id, alliance_id, etc.

    # Extract and validate required fields
    eve_id = character_data["character_id"] || character_data["eve_id"]
    name = character_data["name"]
    corporation_id = character_data["corporation_id"]

    # Validate required fields are present
    cond do
      is_nil(eve_id) ->
        {:error, "Missing required field: character_id or eve_id"}

      is_nil(name) ->
        {:error, "Missing required field: name"}

      is_nil(corporation_id) ->
        {:error, "Missing required field: corporation_id"}

      true ->
        attrs = %{
          eve_id: eve_id,
          name: name,
          corporation_id: corporation_id,
          corporation_ticker: character_data["corporation_ticker"],
          alliance_id: character_data["alliance_id"],
          alliance_ticker: character_data["alliance_ticker"]
        }

        MapCharacter.new_safe(attrs)
    end
  end
end
