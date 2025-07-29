defmodule WandererNotifier.Domains.Notifications.Notifiers.TestNotifier do
  @moduledoc """
  Test notifier for use in test environment.
  This module is the single source of truth for test notifications.
  """

  @behaviour WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour

  require Logger

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_message(message, channel \\ nil) do
    Logger.debug("[TEST] Message", message: message, channel: channel, category: :processor)
    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_embed(title, description, color \\ nil, fields \\ [], channel \\ nil) do
    Logger.debug("[TEST] Embed",
      title: title,
      description: description,
      color: color,
      fields: fields,
      channel: channel,
      category: :processor
    )

    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil, channel \\ nil) do
    Logger.debug("[TEST] File",
      filename: filename,
      file_size: byte_size(file_data),
      title: title || "No title",
      description: description || "No description",
      channel: channel,
      category: :processor
    )

    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_image_embed(title, description, image_url, color \\ nil, channel \\ nil) do
    Logger.debug("[TEST] Image embed",
      title: title,
      description: description,
      image_url: image_url,
      color: color,
      channel: channel,
      category: :processor
    )

    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_enriched_kill_embed(killmail, kill_id) do
    Logger.debug("[TEST] Enriched kill",
      kill_id: kill_id,
      killmail: inspect(killmail, limit: 50),
      category: :processor
    )

    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_new_system_notification(system) do
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
    system_name = Map.get(system, "name") || Map.get(system, :name)

    Logger.debug("[TEST] New system",
      system_id: system_id,
      system_name: system_name,
      category: :processor
    )

    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_new_tracked_character_notification(character) do
    char_id = Map.get(character, "character_id") || Map.get(character, :character_id)
    char_name = Map.get(character, "name") || Map.get(character, :name)

    Logger.debug("[TEST] New character",
      character_id: char_id,
      character_name: char_name,
      category: :processor
    )

    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_kill_notification(kill_data) do
    kill_id = Map.get(kill_data, "killmail_id") || Map.get(kill_data, :killmail_id) || "unknown"
    Logger.debug("[TEST] Kill notification", kill_id: kill_id, category: :processor)
    :ok
  end

  @impl WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  def send_kill_notification(killmail, type, opts) do
    kill_id = Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id) || "unknown"

    Logger.debug("[TEST] Kill notification with type and options",
      kill_id: kill_id,
      type: type,
      opts: inspect(opts),
      category: :processor
    )

    :ok
  end

  @doc """
  Sends a test notification for an activity chart.
  """
  def send_activity_chart_notification(chart_info) do
    Logger.debug("[TEST] Activity chart",
      chart_info: inspect(chart_info),
      category: :processor
    )

    :ok
  end

  @impl true
  def notify(_msg), do: :ok

  @impl true
  def send_discord_embed(_embed), do: {:ok, %{status_code: 200}}

  @impl true
  def send_notification(_type, _data), do: {:ok, %{status_code: 200}}
end
