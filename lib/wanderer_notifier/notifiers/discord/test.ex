defmodule WandererNotifier.Notifiers.Discord.Test do
  @moduledoc """
  Test implementation of the Discord notifier.
  This module is used in test environments to avoid making actual Discord API calls.
  It implements the same interface as the real Discord notifier but logs messages instead.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @behaviour WandererNotifier.Notifiers.Behaviour

  # Implement all required callback functions
  def send_message(message, _feature \\ :general) do
    AppLogger.processor_debug("[TEST] Discord message", message: message)
    :ok
  end

  def send_embed(title, description, url \\ nil, _color \\ nil, _feature \\ :general) do
    AppLogger.processor_debug("[TEST] Discord embed",
      title: title,
      description: description,
      url: url
    )

    :ok
  end

  def send_enriched_kill_embed(enriched_kill, kill_id) do
    AppLogger.processor_debug("[TEST] Discord enriched kill embed",
      kill_id: kill_id,
      enriched_kill: inspect(enriched_kill, limit: 50)
    )

    :ok
  end

  def send_new_tracked_character_notification(character) do
    char_id = Map.get(character, "character_id") || Map.get(character, :character_id)
    char_name = Map.get(character, "name") || Map.get(character, :name)

    AppLogger.processor_debug("[TEST] Discord new character notification",
      character_id: char_id,
      character_name: char_name
    )

    :ok
  end

  def send_new_system_notification(system) do
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
    system_name = Map.get(system, "name") || Map.get(system, :name)

    AppLogger.processor_debug("[TEST] Discord new system notification",
      system_id: system_id,
      system_name: system_name
    )

    :ok
  end

  def send_file(_filename, _file_data, _title \\ nil, _description \\ nil, _feature \\ :general) do
    AppLogger.processor_debug("[TEST] Discord file send")
    :ok
  end
end
