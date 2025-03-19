defmodule WandererNotifier.KillProcessor do
  @moduledoc """
  Proxy module for WandererNotifier.Services.KillProcessor.
  Delegates calls to the Services.KillProcessor implementation.
  """

  @doc """
  Generate and process a test kill notification
  Delegates to WandererNotifier.Services.KillProcessor.send_test_kill_notification/0
  """
  def send_test_kill_notification do
    WandererNotifier.Services.KillProcessor.send_test_kill_notification()
  end

  @doc """
  Get recent kills from the cache
  Delegates to WandererNotifier.Services.KillProcessor.get_recent_kills/0
  """
  def get_recent_kills do
    WandererNotifier.Services.KillProcessor.get_recent_kills()
  end

  @doc """
  Process a zkill websocket message
  Delegates to WandererNotifier.Services.KillProcessor.process_zkill_message/2
  """
  def process_zkill_message(data, state) do
    WandererNotifier.Services.KillProcessor.process_zkill_message(data, state)
  end

  @doc """
  Returns the child_spec for this service
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {WandererNotifier.Services.KillProcessor, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end
