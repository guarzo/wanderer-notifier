defmodule WandererNotifier.Discord.TestNotifier do
  @moduledoc """
  Test-specific implementation of the Discord notifier.
  This module is used in test environment to avoid making actual Discord API calls.
  """
  require Logger

  # Implement the NotifierBehaviour
  @behaviour WandererNotifier.NotifierBehaviour

  @doc """
  Sends a plain text message to Discord.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_message(message) when is_binary(message) do
    Logger.info("DISCORD TEST: #{message}")
    :ok
  end

  @doc """
  Sends a basic embed message to Discord.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_embed(title, description, _url \\ nil, _color \\ 0x00FF00) do
    Logger.info("DISCORD TEST EMBED: #{title} - #{description}")
    :ok
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_enriched_kill_embed(_enriched_kill, kill_id) do
    Logger.info("DISCORD TEST KILL EMBED: Kill ID #{kill_id}")
    :ok
  end

  @doc """
  Sends a notification for a new tracked character.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_new_tracked_character_notification(character) when is_map(character) do
    character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
    Logger.info("DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
    :ok
  end

  @doc """
  Sends a notification for a new system found.
  In test environment, this just logs the message.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_new_system_notification(system) when is_map(system) do
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
    Logger.info("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    :ok
  end

  @doc """
  Sends a file with an optional title and description.
  In test environment, this just logs the information.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil) do
    file_size = byte_size(file_data)
    title_str = if title, do: title, else: "No title"
    desc_str = if description, do: description, else: "No description"

    Logger.info(
      "DISCORD TEST FILE: #{filename} (#{file_size} bytes) - Title: #{title_str}, Description: #{desc_str}"
    )

    :ok
  end

  @doc """
  Sends an embed with an image to Discord.
  In test environment, this just logs the information.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_image_embed(title, description, image_url, _color \\ 0x00FF00) do
    Logger.info("DISCORD TEST IMAGE EMBED: #{title} - #{description} with image: #{image_url}")
    :ok
  end
end
