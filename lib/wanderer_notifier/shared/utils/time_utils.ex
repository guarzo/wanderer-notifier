defmodule WandererNotifier.Shared.Utils.TimeUtils do
  @moduledoc """
  Centralized time and date utilities for WandererNotifier.
  Provides consistent time handling across the application.
  """
  
  require Logger

  @doc """
  Gets the current UTC time as DateTime.
  """
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now()

  @doc """
  Gets the current time in Unix timestamp (seconds).
  """
  @spec now_unix() :: integer()
  def now_unix, do: DateTime.to_unix(now())

  @doc """
  Gets the current time in milliseconds.
  """
  @spec now_ms() :: integer()
  def now_ms, do: System.system_time(:millisecond)

  @doc """
  Gets the current monotonic time in milliseconds.
  Useful for measuring elapsed time.
  """
  @spec monotonic_ms() :: integer()
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @doc """
  Parses an ISO8601 datetime string.
  Returns {:ok, DateTime.t()} or {:error, reason}.
  """
  @spec parse_iso8601(String.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  def parse_iso8601(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_iso8601(_), do: {:error, :invalid_input}

  @doc """
  Parses an ISO8601 datetime string, raising on error.
  """
  @spec parse_iso8601!(String.t()) :: DateTime.t()
  def parse_iso8601!(datetime_string) do
    case parse_iso8601(datetime_string) do
      {:ok, datetime} -> datetime
      {:error, reason} -> raise ArgumentError, "Failed to parse datetime: #{reason}"
    end
  end

  @doc """
  Formats a DateTime to ISO8601 string.
  """
  @spec to_iso8601(DateTime.t()) :: String.t()
  def to_iso8601(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end
  
  # Catch invalid calls and log them for debugging
  def to_iso8601(invalid_input) do
    stack = Process.info(self(), :current_stacktrace) |> elem(1)
    Logger.error("[DEBUG] TimeUtils.to_iso8601 called with invalid input: #{inspect(invalid_input)}")
    Logger.error("[DEBUG] Stacktrace: #{Exception.format_stacktrace(stack)}")
    raise FunctionClauseError, module: __MODULE__, function: :to_iso8601, arity: 1
  end

  @doc """
  Calculates the difference between two DateTimes in seconds.
  """
  @spec diff(DateTime.t(), DateTime.t()) :: integer()
  def diff(%DateTime{} = dt1, %DateTime{} = dt2) do
    DateTime.diff(dt1, dt2)
  end

  @doc """
  Calculates time elapsed since a given DateTime in seconds.
  """
  @spec elapsed_seconds(DateTime.t()) :: integer()
  def elapsed_seconds(%DateTime{} = from) do
    diff(now(), from)
  end

  @doc """
  Calculates time elapsed since a given DateTime in milliseconds.
  """
  @spec elapsed_ms(DateTime.t()) :: integer()
  def elapsed_ms(%DateTime{} = from) do
    elapsed_seconds(from) * 1000
  end

  @doc """
  Formats an uptime duration in seconds to a human-readable string.
  Example: 3661 seconds -> "1h 1m 1s"
  """
  @spec format_uptime(integer()) :: String.t()
  def format_uptime(seconds) when is_integer(seconds) and seconds >= 0 do
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

  def format_uptime(_), do: "0s"

  @doc """
  Formats a duration in milliseconds to a human-readable string.
  Example: 5500 ms -> "5.5s"
  """
  @spec format_duration_ms(integer()) :: String.t()
  def format_duration_ms(ms) when is_integer(ms) and ms >= 1000 do
    seconds = ms / 1000
    :io_lib.format("~.1fs", [seconds]) |> to_string()
  end

  def format_duration_ms(ms) when is_integer(ms) do
    "#{ms}ms"
  end

  def format_duration_ms(_), do: "0ms"

  @doc """
  Formats a timestamp as a relative time string.
  Example: "5 minutes ago", "2 hours ago", "just now"
  """
  @spec format_relative_time(DateTime.t()) :: String.t()
  def format_relative_time(%DateTime{} = datetime) do
    seconds_ago = elapsed_seconds(datetime)

    cond do
      seconds_ago < 10 -> "just now"
      seconds_ago < 60 -> "#{seconds_ago} seconds ago"
      seconds_ago < 120 -> "1 minute ago"
      seconds_ago < 3600 -> "#{div(seconds_ago, 60)} minutes ago"
      seconds_ago < 7200 -> "1 hour ago"
      seconds_ago < 86_400 -> "#{div(seconds_ago, 3600)} hours ago"
      seconds_ago < 172_800 -> "1 day ago"
      true -> "#{div(seconds_ago, 86400)} days ago"
    end
  end

  def format_relative_time(nil), do: "never"

  @doc """
  Converts a Unix timestamp to DateTime.
  """
  @spec from_unix(integer()) :: {:ok, DateTime.t()} | {:error, atom()}
  def from_unix(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  def from_unix(_), do: {:error, :invalid_timestamp}

  @doc """
  Converts a Unix timestamp to DateTime, raising on error.
  """
  @spec from_unix!(integer()) :: DateTime.t()
  def from_unix!(timestamp) do
    case from_unix(timestamp) do
      {:ok, datetime} -> datetime
      {:error, reason} -> raise ArgumentError, "Failed to convert timestamp: #{reason}"
    end
  end

  @doc """
  Adds seconds to a DateTime.
  """
  @spec add_seconds(DateTime.t(), integer()) :: DateTime.t()
  def add_seconds(%DateTime{} = datetime, seconds) when is_integer(seconds) do
    DateTime.add(datetime, seconds, :second)
  end

  @doc """
  Adds milliseconds to a DateTime.
  """
  @spec add_ms(DateTime.t(), integer()) :: DateTime.t()
  def add_ms(%DateTime{} = datetime, ms) when is_integer(ms) do
    DateTime.add(datetime, ms, :millisecond)
  end

  @doc """
  Checks if a DateTime is within a certain age in seconds.
  """
  @spec within_age?(DateTime.t(), integer()) :: boolean()
  def within_age?(%DateTime{} = datetime, max_age_seconds) when is_integer(max_age_seconds) do
    elapsed_seconds(datetime) <= max_age_seconds
  end

  def within_age?(_, _), do: false

  @doc """
  Gets a timestamp for logging purposes.
  Returns ISO8601 formatted string.
  """
  @spec log_timestamp() :: String.t()
  def log_timestamp do
    to_iso8601(now())
  end

  @doc """
  Measures the execution time of a function in milliseconds.
  Returns {result, duration_ms}.
  """
  @spec measure((-> any())) :: {any(), integer()}
  def measure(fun) when is_function(fun, 0) do
    start = monotonic_ms()
    result = fun.()
    duration = monotonic_ms() - start
    {result, duration}
  end
end
