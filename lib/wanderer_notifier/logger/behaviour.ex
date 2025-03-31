defmodule WandererNotifier.Logger.Behaviour do
  @moduledoc """
  Behaviour for logging operations.
  """

  @callback debug(message :: String.t()) :: :ok
  @callback info(message :: String.t()) :: :ok
  @callback warn(message :: String.t()) :: :ok
  @callback error(message :: String.t()) :: :ok

  @callback api_error(message :: String.t()) :: :ok
  @callback api_error(message :: String.t(), metadata :: Keyword.t()) :: :ok

  @callback processor_debug(message :: String.t()) :: :ok
  @callback processor_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok

  @callback processor_info(message :: String.t()) :: :ok
  @callback processor_info(message :: String.t(), metadata :: Keyword.t()) :: :ok

  @callback processor_warn(message :: String.t()) :: :ok
  @callback processor_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok

  @callback processor_error(message :: String.t()) :: :ok
  @callback processor_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
end
