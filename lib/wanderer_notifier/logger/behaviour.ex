defmodule WandererNotifier.Logger.Behaviour do
  @moduledoc """
  Defines the behaviour for the WandererNotifier logger.
  """

  @callback debug(message :: String.t()) :: :ok
  @callback debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback info(message :: String.t()) :: :ok
  @callback info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback warn(message :: String.t()) :: :ok
  @callback warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback error(message :: String.t()) :: :ok
  @callback error(message :: String.t(), metadata :: Keyword.t()) :: :ok

  @callback api_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback processor_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback processor_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback processor_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback processor_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback notification_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback notification_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback notification_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback notification_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback log(
              level :: atom(),
              category :: atom(),
              message :: String.t(),
              metadata :: Keyword.t()
            ) :: :ok

  @callback api_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback api_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback api_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback websocket_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback websocket_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback websocket_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback websocket_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback kill_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback kill_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback kill_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback kill_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback persistence_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback persistence_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback persistence_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback persistence_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback cache_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback cache_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback cache_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback cache_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback startup_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback startup_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback startup_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback startup_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback config_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback config_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback config_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback config_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback maintenance_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback maintenance_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback maintenance_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback maintenance_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback scheduler_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback scheduler_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback scheduler_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback scheduler_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback set_context(metadata :: Keyword.t()) :: :ok
  @callback with_trace_id(metadata :: Keyword.t()) :: Keyword.t()
  @callback generate_trace_id() :: String.t()
  @callback exception(
              level :: atom(),
              category :: atom(),
              message :: String.t(),
              exception :: Exception.t(),
              metadata :: Keyword.t()
            ) :: :ok
  @callback log_kv(level :: atom(), category :: atom(), message :: String.t(), value :: term()) ::
              :ok
  @callback log_full_data(
              level :: atom(),
              category :: atom(),
              message :: String.t(),
              data :: term(),
              metadata :: Keyword.t()
            ) :: :ok
  @callback info_kv(category :: atom(), message :: String.t(), value :: term()) :: :ok
  @callback debug_kv(category :: atom(), message :: String.t(), value :: term()) :: :ok
  @callback warn_kv(category :: atom(), message :: String.t(), value :: term()) :: :ok
  @callback error_kv(category :: atom(), message :: String.t(), value :: term()) :: :ok
  @callback config_kv(message :: String.t(), value :: term()) :: :ok
  @callback startup_kv(message :: String.t(), value :: term()) :: :ok
  @callback cache_kv(message :: String.t(), value :: term()) :: :ok
  @callback websocket_kv(message :: String.t(), value :: term()) :: :ok
  @callback api_kv(message :: String.t(), value :: term()) :: :ok
  @callback maintenance_kv(message :: String.t(), value :: term()) :: :ok
  @callback chart_debug(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback chart_info(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback chart_warn(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback chart_error(message :: String.t(), metadata :: Keyword.t()) :: :ok
  @callback log_with_timing(
              level :: atom(),
              category :: atom(),
              metadata :: Keyword.t(),
              fun :: (-> any())
            ) :: any()
end
