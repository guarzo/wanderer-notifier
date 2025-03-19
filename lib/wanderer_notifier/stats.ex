defmodule WandererNotifier.Stats do
  @moduledoc """
  Proxy module for WandererNotifier.Core.Stats.
  Delegates all calls to the Core.Stats implementation.
  """

  @doc """
  Increments the count for a specific notification type.
  Delegates to WandererNotifier.Core.Stats.increment/1.
  """
  def increment(type) do
    WandererNotifier.Core.Stats.increment(type)
  end

  @doc """
  Returns the current statistics.
  Delegates to WandererNotifier.Core.Stats.get_stats/0.
  """
  def get_stats do
    WandererNotifier.Core.Stats.get_stats()
  end

  @doc """
  Updates the websocket status.
  Delegates to WandererNotifier.Core.Stats.update_websocket/1.
  """
  def update_websocket(status) do
    WandererNotifier.Core.Stats.update_websocket(status)
  end
end
