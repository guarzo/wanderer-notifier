defmodule WandererNotifier.Shared.Utils.TimeUtils do
  @moduledoc """
  Centralized time and date utilities for WandererNotifier.
  Provides consistent time handling across the application.
  """

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
  Formats a DateTime as a compact relative time string.
  Returns a short format like "30s ago", "5m ago", "2h ago", "3d ago".
  Returns the default value (default: "never") for nil input.

  ## Examples

      iex> TimeUtils.format_time_ago(DateTime.add(DateTime.utc_now(), -30, :second))
      "30s ago"

      iex> TimeUtils.format_time_ago(nil)
      "never"

      iex> TimeUtils.format_time_ago(nil, "n/a")
      "n/a"
  """
  @spec format_time_ago(DateTime.t() | nil, String.t()) :: String.t()
  def format_time_ago(datetime, default \\ "never")

  def format_time_ago(nil, default), do: default

  def format_time_ago(%DateTime{} = datetime, _default) do
    seconds = max(elapsed_seconds(datetime), 0)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

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

  @doc """
  Parses an HTTP-date as defined in RFC 7231.
  Supports the preferred format: "Sun, 06 Nov 1994 08:49:37 GMT"

  Returns {:ok, DateTime.t()} or {:error, reason}.
  """
  @spec parse_http_date(String.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  def parse_http_date(date_string) when is_binary(date_string) do
    # HTTP-date format: "Sun, 06 Nov 1994 08:49:37 GMT"
    case String.split(date_string, [" ", ","]) |> Enum.filter(&(&1 != "")) do
      [_day_name, day, month, year, time, "GMT"] ->
        parse_http_date_parts(day, month, year, time)

      _ ->
        {:error, :invalid_http_date}
    end
  end

  def parse_http_date(_), do: {:error, :invalid_input}

  defp parse_http_date_parts(day, month, year, time) do
    with {:ok, month_num} <- month_to_number(month),
         {day_num, ""} <- Integer.parse(day),
         {year_num, ""} <- Integer.parse(year),
         {:ok, time_parts} <- parse_time_string(time),
         {:ok, datetime} <- build_http_datetime(year_num, month_num, day_num, time_parts) do
      {:ok, datetime}
    else
      _ -> {:error, :invalid_http_date}
    end
  end

  defp parse_time_string(time_string) do
    case String.split(time_string, ":") do
      [hour, minute, second] ->
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minute),
             {s, ""} <- Integer.parse(second) do
          {:ok, {h, m, s}}
        else
          _ -> {:error, :invalid_time}
        end

      _ ->
        {:error, :invalid_time_format}
    end
  end

  defp build_http_datetime(year, month, day, {hour, minute, second}) do
    with {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- Time.new(hour, minute, second),
         {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
      {:ok, datetime}
    else
      _ -> {:error, :invalid_datetime}
    end
  end

  @month_map %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  defp month_to_number(month) when is_map_key(@month_map, month) do
    {:ok, @month_map[month]}
  end

  defp month_to_number(_), do: {:error, :invalid_month}
end
