defmodule WandererNotifier.Logger.LoggerBehaviour do
  @moduledoc """
  Behaviour for application logging.
  Defines the contract for modules that handle application logging.
  """

  @doc """
  Logs a notification info message.

  ## Parameters
  - message: The message to log
  - meta: Additional metadata to include in the log
  """
  @callback notification_info(message :: String.t(), meta :: map()) :: :ok

  @doc """
  Logs a notification error message.

  ## Parameters
  - message: The message to log
  - meta: Additional metadata to include in the log
  """
  @callback notification_error(message :: String.t(), meta :: map()) :: :ok
end
