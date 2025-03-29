defmodule WandererNotifier.Notifiers.TestNotifier do
  @moduledoc """
  Test notifier for development and testing purposes.
  """

  require Logger

  @doc """
  Sends a test notification for a new tracked character.
  """
  def send_new_tracked_character_notification(character_info) do
    Logger.info(
      "TEST NOTIFIER: Would send notification for new tracked character: #{inspect(character_info)}"
    )

    :ok
  end

  @doc """
  Sends a test notification for a new system.
  """
  def send_new_system_notification(system_info) do
    Logger.info("TEST NOTIFIER: Would send notification for new system: #{inspect(system_info)}")
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
