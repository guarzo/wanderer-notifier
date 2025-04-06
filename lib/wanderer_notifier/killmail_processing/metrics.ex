defmodule WandererNotifier.KillmailProcessing.Metrics do
  @moduledoc """
  Metrics collection and reporting for killmail processing.
  """

  alias WandererNotifier.KillmailProcessing.Context
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Agent name for metrics storage
  @agent_name :killmail_metrics_agent

  # Registered metrics that are allowed to be tracked
  @registered_metrics %{
    # Base processing metrics for all modes
    "killmail.processing.realtime.start" => :counter,
    "killmail.processing.historical.start" => :counter,
    "killmail.processing.manual.start" => :counter,
    "killmail.processing.batch.start" => :counter,

    # Complete metrics for all modes with success/error variants
    "killmail.processing.realtime.complete" => :counter,
    "killmail.processing.historical.complete" => :counter,
    "killmail.processing.manual.complete" => :counter,
    "killmail.processing.batch.complete" => :counter,
    "killmail.processing.realtime.complete.success" => :counter,
    "killmail.processing.historical.complete.success" => :counter,
    "killmail.processing.manual.complete.success" => :counter,
    "killmail.processing.batch.complete.success" => :counter,
    "killmail.processing.realtime.complete.error" => :counter,
    "killmail.processing.historical.complete.error" => :counter,
    "killmail.processing.manual.complete.error" => :counter,
    "killmail.processing.batch.complete.error" => :counter,

    # Skipped metrics for all modes
    "killmail.processing.realtime.skipped" => :counter,
    "killmail.processing.historical.skipped" => :counter,
    "killmail.processing.manual.skipped" => :counter,
    "killmail.processing.batch.skipped" => :counter,

    # Error metrics for all modes
    "killmail.processing.realtime.error" => :counter,
    "killmail.processing.historical.error" => :counter,
    "killmail.processing.manual.error" => :counter,
    "killmail.processing.batch.error" => :counter,

    # Persistence metrics for all modes
    "killmail.persistence.realtime" => :counter,
    "killmail.persistence.historical" => :counter,
    "killmail.persistence.manual" => :counter,
    "killmail.persistence.batch" => :counter,

    # Notification metrics for all modes
    "killmail.notification.realtime.sent" => :counter,
    "killmail.notification.historical.sent" => :counter,
    "killmail.notification.manual.sent" => :counter,
    "killmail.notification.batch.sent" => :counter
  }

  @doc """
  Required child_spec implementation for supervisor integration.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc """
  Initializes the metrics agent.
  Call this during application startup before using any metrics functions.
  """
  def start_link(_opts \\ []) do
    # Initialize the agent with the initial state
    initial_state = %{
      counters: %{},
      timestamp: DateTime.utc_now()
    }

    # Start the agent with a name
    result = Agent.start_link(fn -> initial_state end, name: @agent_name)

    # Synchronize with metric registry
    synchronize_registry()

    result
  end

  @doc """
  Synchronizes the registered metrics with the metric registry to avoid errors.
  """
  def synchronize_registry do
    alias WandererNotifier.KillmailProcessing.MetricRegistry

    # Get all registered metrics from the registry
    registry_metrics = MetricRegistry.registered_metrics()

    # Convert atom metrics to strings
    registry_metric_strings = Enum.map(registry_metrics, &Atom.to_string/1)

    # Find metrics that are in the registry but not in @registered_metrics
    missing_metrics =
      Enum.filter(registry_metric_strings, fn metric_string ->
        !Map.has_key?(@registered_metrics, metric_string)
      end)

    # Log any discrepancies
    if !Enum.empty?(missing_metrics) do
      AppLogger.startup_warn(
        "Found metrics in registry that aren't in @registered_metrics map",
        %{count: length(missing_metrics), metrics: Enum.take(missing_metrics, 5)}
      )
    end

    # No need to modify @registered_metrics at runtime since it's a module attribute
    # This function primarily serves as a diagnostic tool

    :ok
  end

  @doc """
  Resets all counters to zero.
  """
  def reset_counters do
    Agent.update(@agent_name, fn state ->
      %{state | counters: %{}, timestamp: DateTime.utc_now()}
    end)
  end

  @doc """
  Gets the current counter values.
  """
  def get_counters do
    Agent.get(@agent_name, fn state -> state.counters end)
  end

  @doc """
  Tracks the start of killmail processing.
  """
  @spec track_processing_start(Context.t()) :: :ok
  def track_processing_start(%Context{} = ctx) do
    metric_key = "killmail.processing.#{mode_name(ctx)}.start"
    increment_counter(metric_key)
    :ok
  end

  @doc """
  Tracks the completion of killmail processing.
  """
  @spec track_processing_complete(Context.t(), {:ok, term()} | {:error, term()}) :: :ok
  def track_processing_complete(%Context{} = ctx, result) do
    base_metric = "processing.#{mode_name(ctx)}.complete"
    track_metric(ctx, base_metric)

    case result do
      {:ok, _} ->
        increment_counter("killmail.#{base_metric}.success")

      {:error, _} ->
        increment_counter("killmail.#{base_metric}.error")
    end

    :ok
  end

  @doc """
  Tracks when a killmail is skipped.
  """
  @spec track_processing_skipped(Context.t()) :: :ok
  def track_processing_skipped(%Context{} = ctx) do
    metric_key = "killmail.processing.#{mode_name(ctx)}.skipped"
    increment_counter(metric_key)
    :ok
  end

  @doc """
  Tracks when a killmail processing fails.
  """
  @spec track_processing_error(Context.t()) :: :ok
  def track_processing_error(%Context{} = ctx) do
    metric_key = "killmail.processing.#{mode_name(ctx)}.error"
    increment_counter(metric_key)
    :ok
  end

  @doc """
  Tracks when a killmail is persisted.
  """
  @spec track_persistence(Context.t()) :: :ok
  def track_persistence(%Context{} = ctx), do: track_metric(ctx, "persistence")

  @doc """
  Tracks a notification being sent.
  """
  @spec track_notification_sent(Context.t()) :: :ok
  def track_notification_sent(%Context{} = ctx) do
    metric_key = "killmail.notification.#{mode_name(ctx)}.sent"
    increment_counter(metric_key)
    :ok
  end

  # Private functions

  # Generic function to track metrics with a specific key pattern
  defp track_metric(%Context{} = ctx, operation) do
    metric_key = "killmail.#{operation}.#{mode_name(ctx)}"
    increment_counter(metric_key)
    :ok
  end

  defp mode_name(%Context{mode: %{mode: mode}}), do: Atom.to_string(mode)

  defp increment_counter(key) do
    # Track metrics using Core Stats
    increment_counter_impl(key)
  end

  defp increment_counter_impl({counter, value}) do
    current_value = Agent.get(@agent_name, fn state -> Map.get(state.counters, counter, 0) end)
    new_value = current_value + value

    # First, check if the counter is already in the warning cache
    warning_cache_key = {:metric_warning, counter}
    already_warned = Process.get(warning_cache_key, false)

    if Map.has_key?(@registered_metrics, counter) do
      # Valid metric, update the counter
      Agent.update(@agent_name, fn state ->
        counters = Map.put(state.counters, counter, new_value)
        %{state | counters: counters}
      end)
    else
      # Still track the metric even if it's not registered to avoid data loss
      Agent.update(@agent_name, fn state ->
        counters = Map.put(state.counters, counter, new_value)
        %{state | counters: counters}
      end)

      # Only log the warning once per key to reduce log spam
      if !already_warned do
        AppLogger.processor_warn("Attempted to track metrics with non-registered key", %{
          counter: counter,
          value: value
        })

        # Mark this key as already warned about
        Process.put(warning_cache_key, true)
      end
    end
  rescue
    e ->
      AppLogger.processor_error("Error tracking metric", %{
        counter: counter,
        value: value,
        error: Exception.message(e)
      })
  end

  defp increment_counter_impl(key) when is_binary(key) do
    # For simple string keys, use a default value of 1
    increment_counter_impl({key, 1})
  end
end
