defmodule WandererNotifier.Shared.Utils.Startup do
  @moduledoc """
  Utilities for handling startup-related operations including suppression periods.

  Provides logic for determining if the application is within the startup
  suppression period, which avoids notification spam during initial synchronization.
  """

  @doc """
  Checks if the application is currently within the startup suppression period.

  The suppression period begins when the application starts (based on the :start_time
  configuration) and lasts for the configured suppression duration (default: 30 seconds).

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
      elapsed_seconds < suppression_seconds_config()
    else
      # If no start time is set, don't suppress
      false
    end
  end

  @doc """
  Returns the startup suppression period in seconds from configuration.
  Defaults to 30 seconds if not configured.
  """
  @spec suppression_seconds() :: pos_integer()
  def suppression_seconds, do: suppression_seconds_config()

  # Private function to get suppression seconds from config
  defp suppression_seconds_config do
    Application.get_env(:wanderer_notifier, :startup_suppression_seconds, 30)
  end
end
