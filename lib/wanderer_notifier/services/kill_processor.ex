defmodule WandererNotifier.Services.KillProcessor do
  @moduledoc """
  Processes killmail data from various sources.
  This module is responsible for analyzing killmail data, determining what actions
  to take, and orchestrating notifications as needed.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Processing.Killmail.Processor instead.
  """

  require Logger

  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.Processor, as: KillmailProcessor

  @doc """
  Initialize statistics tracking.
  Sets up the initial counters in process dictionary.
  """
  def init_stats do
    AppLogger.kill_warn(
      "KillProcessor.init_stats is deprecated, please use WandererNotifier.Processing.Killmail.Processor.init instead"
    )

    KillmailProcessor.init()
  end

  @doc """
  Schedule periodic logging of kill statistics.
  """
  def schedule_stats_logging do
    AppLogger.kill_warn(
      "KillProcessor.schedule_stats_logging is deprecated, please use WandererNotifier.Processing.Killmail.Processor.schedule_tasks instead"
    )

    KillmailProcessor.schedule_tasks()
  end

  @doc """
  Log the current kill statistics.
  Shows processed kills, notifications, last kill time, and uptime.
  """
  def log_kill_stats do
    AppLogger.kill_warn(
      "KillProcessor.log_kill_stats is deprecated, please use WandererNotifier.Processing.Killmail.Processor.log_stats instead"
    )

    KillmailProcessor.log_stats()
  end

  @doc """
  Process a websocket message from zKillboard.
  Handles both text and map messages, routing them to the appropriate handlers.

  Returns an updated state that tracks processed kills.
  """
  def process_zkill_message(message, state) do
    AppLogger.kill_warn(
      "KillProcessor.process_zkill_message is deprecated, please use WandererNotifier.Processing.Killmail.Processor.process_zkill_message instead"
    )

    KillmailProcessor.process_zkill_message(message, state)
  end

  @doc """
  Gets a list of recent kills from the cache.
  """
  def get_recent_kills do
    AppLogger.kill_warn(
      "KillProcessor.get_recent_kills is deprecated, please use WandererNotifier.Processing.Killmail.Processor.get_recent_kills instead"
    )

    KillmailProcessor.get_recent_kills()
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    AppLogger.kill_warn(
      "KillProcessor.send_test_kill_notification is deprecated, please use WandererNotifier.Processing.Killmail.Processor.send_test_kill_notification instead"
    )

    KillmailProcessor.send_test_kill_notification()
  end
end
