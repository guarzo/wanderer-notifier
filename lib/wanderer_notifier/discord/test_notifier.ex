defmodule WandererNotifier.Discord.TestNotifier do
  @moduledoc """
  Test-specific implementation of the Discord notifier.
  This module is used in test environment to avoid making actual Discord API calls.
  """
  alias WandererNotifier.Core.Logger, as: AppLogger

  # Implement the NotifierBehaviour
  @behaviour WandererNotifier.Notifiers.Behaviour

  @doc """
  Sends a plain text message to Discord.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_message(message, _feature \\ nil) when is_binary(message) do
    AppLogger.processor_info("Discord test message", message: message)
    :ok
  end

  @doc """
  Sends a basic embed message to Discord.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_embed(title, description, _url \\ nil, _color \\ 0x00FF00, _feature \\ nil) do
    AppLogger.processor_info("Discord test embed", title: title, description: description)
    :ok
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(_enriched_kill, kill_id) do
    AppLogger.processor_info("Discord test kill embed", kill_id: kill_id)
    :ok
  end

  @doc """
  Sends a notification for a new tracked character.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_tracked_character_notification(character) when is_map(character) do
    character_id = Map.get(character, "character_id") || Map.get(character, :character_id)
    AppLogger.processor_info("Discord test character notification", character_id: character_id)
    :ok
  end

  @doc """
  Sends a notification for a new system found.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_system_notification(system) when is_map(system) do
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
    AppLogger.processor_info("Discord test system notification", system_id: system_id)
    :ok
  end

  @doc """
  Sends a file with an optional title and description.
  In test environment, this just logs the information.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil, _feature \\ nil) do
    file_size = byte_size(file_data)
    title_str = if title, do: title, else: "No title"
    desc_str = if description, do: description, else: "No description"

    AppLogger.processor_info("Discord test file",
      filename: filename,
      file_size: file_size,
      title: title_str,
      description: desc_str
    )

    :ok
  end

  @doc """
  Sends an embed with an image to Discord.
  In test environment, this just logs the information.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_image_embed(title, description, image_url, _color \\ 0x00FF00, _feature \\ nil) do
    AppLogger.processor_info("Discord test image embed",
      title: title,
      description: description,
      image_url: image_url
    )

    :ok
  end

  @doc """
  Sends a notification about a killmail.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_kill_notification(kill_data) do
    kill_id = Map.get(kill_data, "killmail_id") || Map.get(kill_data, :killmail_id) || "unknown"
    AppLogger.processor_info("Discord test kill notification", kill_id: kill_id)
    :ok
  end
end
