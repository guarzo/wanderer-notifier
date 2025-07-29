defmodule WandererNotifier.Shared.Utils.Startup do
  @moduledoc """
  Utilities for handling startup-related operations including suppression periods.

  This module provides centralized logic for determining if the application is within
  the startup suppression period, which is used to avoid notification spam during
  initial system synchronization.
  """

  # Suppress notifications for 30 seconds after startup to avoid spam from initial sync
  @startup_suppression_seconds 30

  @doc """
  Checks if the application is currently within the startup suppression period.

  The suppression period begins when the application starts (based on the :start_time
  configuration) and lasts for #{@startup_suppression_seconds} seconds.

  ## Returns

  - `true` if within the suppression period
  - `false` if outside the suppression period or if no start time is configured

  ## Examples

      iex> WandererNotifier.Shared.Utils.Startup.in_suppression_period?()
      false
  """
  @spec in_suppression_period?() :: boolean()
  def in_suppression_period? do
    start_time = Application.get_env(:wanderer_notifier, :start_time)

    if start_time do
      current_time = :erlang.monotonic_time(:second)
      elapsed_seconds = current_time - start_time
      elapsed_seconds < @startup_suppression_seconds
    else
      # If no start time is set, don't suppress
      false
    end
  end

  @doc """
  Returns the startup suppression period in seconds.
  """
  @spec suppression_seconds() :: pos_integer()
  def suppression_seconds, do: @startup_suppression_seconds
end
