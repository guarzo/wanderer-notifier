defmodule WandererNotifier.Helpers.TimeHelper do
  @moduledoc """
  Helper functions for time-related operations.
  """

  @doc """
  Formats uptime in seconds into a human-readable string.

  ## Examples
      iex> TimeHelper.format_uptime(3665)
      "1h 1m 5s"
  """
  def format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86_400)
    seconds = rem(seconds, 86_400)
    hours = div(seconds, 3600)
    seconds = rem(seconds, 3600)
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m #{seconds}s"
      hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
      minutes > 0 -> "#{minutes}m #{seconds}s"
      true -> "#{seconds}s"
    end
  end

  def format_uptime(_), do: "Unknown"
end
