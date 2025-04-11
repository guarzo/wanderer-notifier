defmodule WandererNotifier.Processing.Killmail.Processor do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Processing.WebsocketProcessor instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Processing.WebsocketProcessor.
  """

  alias WandererNotifier.Killmail.Processing.WebsocketProcessor

  @behaviour WandererNotifier.Processing.Killmail.ProcessorBehaviour

  @impl WandererNotifier.Processing.Killmail.ProcessorBehaviour
  def init, do: WebsocketProcessor.init()

  def schedule_tasks, do: WebsocketProcessor.schedule_tasks()

  def log_stats, do: WebsocketProcessor.log_stats()

  def process_zkill_message(message, state),
    do: WebsocketProcessor.process_zkill_message(message, state)

  @impl WandererNotifier.Processing.Killmail.ProcessorBehaviour
  def get_recent_kills, do: WebsocketProcessor.get_recent_kills()

  def send_test_kill_notification, do: WebsocketProcessor.send_test_kill_notification()

  def handle_message(message, state), do: WebsocketProcessor.handle_message(message, state)

  def process_single_kill(kill, ctx), do: WebsocketProcessor.process_single_kill(kill, ctx)
end
