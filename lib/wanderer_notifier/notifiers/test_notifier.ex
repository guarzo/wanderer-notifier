defmodule WandererNotifier.Notifiers.TestNotifier do
  @moduledoc """
  Test notifier for use in test environment.
  """

  @behaviour WandererNotifier.NotifierBehaviour

  require Logger

  @impl true
  def send_message(message) do
    Logger.info("TEST NOTIFIER: #{message}")
    :ok
  end

  @impl true
  def send_embed(title, description, url \\ nil, color \\ nil) do
    Logger.info("TEST NOTIFIER EMBED: #{title} - #{description} (#{url}) [#{color}]")
    :ok
  end

  @impl true
  def send_file(filename, _file_data, title \\ nil, description \\ nil) do
    Logger.info("TEST NOTIFIER FILE: #{filename} - #{title} - #{description}")
    :ok
  end

  @impl true
  def send_image_embed(title, description, image_url, color \\ nil) do
    Logger.info("TEST NOTIFIER IMAGE: #{title} - #{description} - #{image_url} [#{color}]")
    :ok
  end

  @impl true
  def send_enriched_kill_embed(killmail, kill_id) do
    Logger.info("TEST NOTIFIER KILL: #{inspect(killmail)} - #{kill_id}")
    :ok
  end

  @impl true
  def send_kill_embed(kill, kill_id) do
    Logger.info("TEST NOTIFIER KILL: #{inspect(kill)} - #{kill_id}")
    :ok
  end

  @impl true
  def send_new_system_notification(system) do
    Logger.info("TEST NOTIFIER SYSTEM: #{inspect(system)}")
    :ok
  end

  @impl true
  def send_new_tracked_character_notification(character) do
    Logger.info("TEST NOTIFIER CHARACTER: #{inspect(character)}")
    :ok
  end

  @doc """
  Sends a test notification for a new kill.
  """
  def send_new_kill_notification(kill_info) do
    Logger.info("TEST NOTIFIER: Would send notification for new kill: #{inspect(kill_info)}")
    :ok
  end

  @doc """
  Sends a test notification for an activity chart.
  """
  def send_activity_chart_notification(chart_info) do
    Logger.info(
      "TEST NOTIFIER: Would send notification for activity chart: #{inspect(chart_info)}"
    )

    :ok
  end
end
