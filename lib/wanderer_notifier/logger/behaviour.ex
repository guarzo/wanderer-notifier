defmodule WandererNotifier.Logger.Behaviour do
  @moduledoc """
  Behaviour for logging operations in WandererNotifier.

  This module defines the contract for all logging functions across the application,
  ensuring consistent logging patterns.
  """

  # Base log level callbacks
  @callback debug(message :: String.t()) :: :ok
  @callback info(message :: String.t()) :: :ok
  @callback warn(message :: String.t()) :: :ok
  @callback error(message :: String.t()) :: :ok

  # Base log level callbacks with metadata
  @callback debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Category-specific logging with metadata
  @callback log(
              level :: atom(),
              category :: atom(),
              message :: String.t(),
              metadata :: Keyword.t() | map()
            ) :: :ok

  # Key-value style logging
  @callback log_kv(level :: atom(), category :: atom(), message :: String.t(), value :: any()) ::
              :ok
  @callback info_kv(category :: atom(), message :: String.t(), value :: any()) :: :ok
  @callback debug_kv(category :: atom(), message :: String.t(), value :: any()) :: :ok
  @callback warn_kv(category :: atom(), message :: String.t(), value :: any()) :: :ok
  @callback error_kv(category :: atom(), message :: String.t(), value :: any()) :: :ok

  # Category-specific key-value logging
  @callback startup_kv(message :: String.t(), value :: any()) :: :ok
  @callback config_kv(message :: String.t(), value :: any()) :: :ok
  @callback cache_kv(message :: String.t(), value :: any()) :: :ok
  @callback api_kv(message :: String.t(), value :: any()) :: :ok
  @callback websocket_kv(message :: String.t(), value :: any()) :: :ok
  @callback maintenance_kv(message :: String.t(), value :: any()) :: :ok

  # Various category logging functions
  # API
  @callback api_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback api_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback api_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback api_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # WebSocket
  @callback websocket_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback websocket_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback websocket_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback websocket_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Kill processing
  @callback kill_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback kill_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback kill_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback kill_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Processor
  @callback processor_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback processor_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback processor_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback processor_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Persistence
  @callback persistence_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback persistence_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback persistence_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback persistence_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Startup
  @callback startup_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback startup_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback startup_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback startup_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Cache
  @callback cache_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback cache_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback cache_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback cache_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Config
  @callback config_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback config_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback config_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback config_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Maintenance
  @callback maintenance_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback maintenance_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback maintenance_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback maintenance_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Scheduler
  @callback scheduler_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback scheduler_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback scheduler_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback scheduler_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Chart
  @callback chart_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback chart_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback chart_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback chart_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Notification
  @callback notification_debug(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback notification_info(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback notification_warn(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok
  @callback notification_error(message :: String.t(), metadata :: Keyword.t() | map()) :: :ok

  # Advanced logging
  @callback log_full_data(
              level :: atom(),
              category :: atom(),
              message :: String.t(),
              data :: any(),
              metadata :: Keyword.t() | map()
            ) :: :ok
  @callback exception(
              level :: atom(),
              category :: atom(),
              message :: String.t(),
              exception :: Exception.t(),
              metadata :: Keyword.t() | map()
            ) :: :ok

  # Performance timing
  @callback log_with_timing(
              level :: atom(),
              category :: String.t(),
              metadata :: Keyword.t() | map(),
              fun :: (-> any())
            ) :: any()

  # Trace context
  @callback with_trace_id(metadata :: Keyword.t() | map()) :: String.t()
  @callback set_context(metadata :: Keyword.t() | map()) :: :ok
  @callback generate_trace_id() :: String.t()
end
