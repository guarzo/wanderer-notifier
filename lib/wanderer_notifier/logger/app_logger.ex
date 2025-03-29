defmodule WandererNotifier.Logger.AppLogger do
  @moduledoc """
  Application logger for WandererNotifier.
  """

  require Logger

  @doc """
  Logs a debug message with processor information.
  """
  def processor_debug(message, opts \\ []) do
    Logger.debug(fn -> "[Processor] #{message} #{format_opts(opts)}" end)
  end

  @doc """
  Logs an info message with processor information.
  """
  def processor_info(message, opts \\ []) do
    Logger.info(fn -> "[Processor] #{message} #{format_opts(opts)}" end)
  end

  @doc """
  Logs a warning message with processor information.
  """
  def processor_warning(message, opts \\ []) do
    Logger.warning(fn -> "[Processor] #{message} #{format_opts(opts)}" end)
  end

  @doc """
  Logs an error message with processor information.
  """
  def processor_error(message, opts \\ []) do
    Logger.error(fn -> "[Processor] #{message} #{format_opts(opts)}" end)
  end

  defp format_opts([]), do: ""
  defp format_opts(opts), do: "(#{Enum.map_join(opts, ", ", fn {k, v} -> "#{k}: #{v}" end)})"
end
