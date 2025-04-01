defmodule WandererNotifier.Utils.TimeHelpers do
  @moduledoc """
  Common time-related utility functions.
  Used across the application for consistent time formatting and manipulation.
  """

  @doc """
  Formats uptime in seconds into a human-readable string.

  ## Examples
      iex> TimeHelpers.format_uptime(3665)
      "1h 1m 5s"
      iex> TimeHelpers.format_uptime(90061)
      "1d 1h 1m 1s"
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

  @doc """
  Formats a DateTime into a human-readable string.

  ## Examples
      iex> TimeHelpers.format_datetime(~U[2024-03-31 10:00:00Z])
      "2024-03-31 10:00:00 UTC"
  """
  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")
  end

  def format_datetime(_), do: "Unknown"

  @doc """
  Returns the current timestamp in milliseconds since epoch.
  """
  def current_timestamp_ms do
    :os.system_time(:millisecond)
  end

  @doc """
  Converts a timestamp in milliseconds to a DateTime.

  ## Examples
      iex> TimeHelpers.ms_to_datetime(1711872000000)
      ~U[2024-03-31 10:00:00Z]
  """
  def ms_to_datetime(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(div(timestamp, 1000))
  end

  def ms_to_datetime(_), do: nil
end
