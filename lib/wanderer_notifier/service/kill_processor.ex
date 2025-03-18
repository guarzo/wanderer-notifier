defmodule WandererNotifier.Service.KillProcessor do
  @moduledoc """
  Proxy module for WandererNotifier.Services.KillProcessor.
  Delegates all calls to the Services.KillProcessor implementation.
  """

  @doc """
  Delegates to WandererNotifier.Services.KillProcessor.get_recent_kills/0
  """
  def get_recent_kills do
    WandererNotifier.Services.KillProcessor.get_recent_kills()
  end

  @doc """
  Delegates to WandererNotifier.Services.KillProcessor.send_test_kill_notification/0
  """
  def send_test_kill_notification do
    WandererNotifier.Services.KillProcessor.send_test_kill_notification()
  end

  @doc """
  Delegates to WandererNotifier.Services.KillProcessor.process_zkill_message/2
  """
  def process_zkill_message(message, state) do
    WandererNotifier.Services.KillProcessor.process_zkill_message(message, state)
  end
end
