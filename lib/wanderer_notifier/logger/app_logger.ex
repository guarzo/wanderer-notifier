defmodule WandererNotifier.Logger.AppLogger do
  @moduledoc """
  DEPRECATED: This module exists for backwards compatibility.

  Please use WandererNotifier.Logger.Logger directly for all new code.
  This module simply forwards calls to the main Logger implementation.
  """

  alias WandererNotifier.Logger.Logger

  @doc """
  Logs a debug message with processor information.
  """
  def processor_debug(message, opts \\ []) do
    Logger.processor_debug(message, opts)
  end

  @doc """
  Logs an info message with processor information.
  """
  def processor_info(message, opts \\ []) do
    Logger.processor_info(message, opts)
  end

  @doc """
  Logs a warning message with processor information.
  """
  def processor_warning(message, opts \\ []) do
    Logger.processor_warn(message, opts)
  end

  @doc """
  Logs an error message with processor information.
  """
  def processor_error(message, opts \\ []) do
    Logger.processor_error(message, opts)
  end
end
