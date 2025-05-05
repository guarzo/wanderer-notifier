defmodule WandererNotifier.Killmail.Metrics do
  @moduledoc """
  Metrics collection and reporting for killmail processing.
  """

  alias WandererNotifier.Killmail.Context
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
    alias WandererNotifier.Killmail.MetricRegistry

    # Get all registered metrics from the registry
    registry_metrics = MetricRegistry.registered_metrics()

    # Convert atom metrics to strings
    registry_metric_strings = Enum.map(registry_metrics, &Atom.to_string/1)

    # Find metrics that are in the registry but not in @registered_metrics
    missing_from_metrics =
      Enum.filter(registry_metric_strings, fn metric_string ->
        !Map.has_key?(@registered_metrics, metric_string)
      end)

    # Find metrics that are in @registered_metrics but not in registry
    missing_from_registry =
      Enum.filter(Map.keys(@registered_metrics), fn metric_key ->
        !Enum.member?(registry_metric_strings, metric_key)
      end)

    # Log any discrepancies
    cond do
      # Both lists have discrepancies
      !Enum.empty?(missing_from_metrics) && !Enum.empty?(missing_from_registry) ->
        log_metric_discrepancies(
          missing_from_metrics,
          missing_from_registry,
          "Metrics discrepancies found in both directions"
        )

      # Only registry has metrics that aren't in @registered_metrics
      !Enum.empty?(missing_from_metrics) ->
        log_metric_discrepancies(
          missing_from_metrics,
          [],
          "Found metrics in registry that aren't in @registered_metrics map"
        )

      # Only @registered_metrics has metrics that aren't in registry
      !Enum.empty?(missing_from_registry) ->
        log_metric_discrepancies(
          [],
          missing_from_registry,
          "Found metrics in @registered_metrics that aren't in registry"
        )

      # Everything is in sync
      true ->
        AppLogger.startup_debug("Metrics registry is in sync", %{
          metric_count: length(registry_metric_strings)
        })
    end

    :ok
  end

  # Helper function to log metric discrepancies in a useful way
  defp log_metric_discrepancies(missing_from_metrics, missing_from_registry, message) do
    # Log a summary warning with counts
    AppLogger.startup_warn(message, %{
      missing_from_metrics_count: length(missing_from_metrics),
      missing_from_registry_count: length(missing_from_registry),
      first_few_from_metrics: Enum.take(missing_from_metrics, 3),
      first_few_from_registry: Enum.take(missing_from_registry, 3)
    })

    # Log details about metrics missing from @registered_metrics
    if !Enum.empty?(missing_from_metrics) do
      log_missing_metrics_chunks(missing_from_metrics)
    end

    # Log details about metrics missing from registry
    if !Enum.empty?(missing_from_registry) do
      log_missing_registry_chunks(missing_from_registry)
    end

    # Provide instructions
    log_help_message(missing_from_metrics, missing_from_registry)
  end

  # Helper to log chunks of missing metrics
  defp log_missing_metrics_chunks(missing_metrics) do
    Enum.chunk_every(missing_metrics, 10)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, idx} ->
      # Format for easy copy/paste to add to @registered_metrics
      formatted_metrics = format_metric_chunk(chunk)

      AppLogger.startup_debug(
        "Missing from @registered_metrics (chunk #{idx + 1})",
        %{metrics_for_copy_paste: "\n    #{formatted_metrics}"}
      )
    end)
  end

  # Format a chunk of metrics using map_join for efficiency
  defp format_metric_chunk(chunk) do
    Enum.map_join(chunk, ",\n    ", fn metric ->
      ~s("#{metric}" => :counter)
    end)
  end

  # Helper to log chunks of missing registry items
  defp log_missing_registry_chunks(missing_registry) do
    Enum.chunk_every(missing_registry, 10)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, idx} ->
      AppLogger.startup_debug(
        "Missing from registry (chunk #{idx + 1})",
        %{metrics: chunk}
      )
    end)
  end

  # Log helpful information for solving the discrepancy
  defp log_help_message(missing_from_metrics, missing_from_registry) do
    cond do
      !Enum.empty?(missing_from_metrics) && !Enum.empty?(missing_from_registry) ->
        AppLogger.startup_warn(
          "ACTION REQUIRED: Update both modules to sync metrics. " <>
            "Add missing metrics to @registered_metrics and update MetricRegistry.build_metric_keys/0"
        )

      !Enum.empty?(missing_from_metrics) ->
        AppLogger.startup_warn(
          "ACTION REQUIRED: Update @registered_metrics to include metrics from registry"
        )

      !Enum.empty?(missing_from_registry) ->
        AppLogger.startup_warn(
          "ACTION REQUIRED: Update MetricRegistry.build_metric_keys/0 to register all needed metrics"
        )

      true ->
        :ok
    end
  end

  @doc """
  Tracks the start of killmail processing.
  """
  def track_processing_start(%Context{} = ctx) do
    track_metric(processing_metric(ctx, "start"))
  end

  @doc """
  Tracks the completion of killmail processing.
  """
  def track_processing_complete(%Context{} = ctx, result) do
    # Track the base completion metric
    track_metric(processing_metric(ctx, "complete"))

    # Also track success or error specifically
    status = if match?({:ok, _}, result), do: "success", else: "error"
    track_metric(processing_metric(ctx, "complete.#{status}"))
  end

  @doc """
  Tracks a skipped killmail.
  """
  def track_processing_skipped(%Context{} = ctx) do
    track_metric(processing_metric(ctx, "skipped"))
  end

  @doc """
  Tracks a processing error.
  """
  def track_processing_error(%Context{} = ctx) do
    track_metric(processing_metric(ctx, "error"))
  end

  @doc """
  Tracks a notification being sent.
  """
  def track_notification_sent(%Context{} = ctx) do
    mode_name = get_mode_name(ctx)
    track_metric("killmail.notification.#{mode_name}.sent")
  end

  @doc """
  Tracks a killmail being persisted.
  """
  def track_persistence(%Context{} = ctx) do
    mode_name = get_mode_name(ctx)
    track_metric("killmail.persistence.#{mode_name}")
  end

  # Helper to build a processing metric name
  defp processing_metric(%Context{} = ctx, operation) do
    mode_name = get_mode_name(ctx)
    "killmail.processing.#{mode_name}.#{operation}"
  end

  # Helper to get the mode name as a string
  defp get_mode_name(%Context{mode: %{mode: mode}}), do: Atom.to_string(mode)
  defp get_mode_name(_), do: "manual"

  # Core tracking function that updates counters
  defp track_metric(metric_name) do
    metric_atom = String.to_atom(metric_name)

    # Check if the metric is registered to avoid atom leaks
    if Map.has_key?(@registered_metrics, metric_name) do
      try do
        Agent.update(@agent_name, fn state ->
          # Update the counter for this metric
          updated_counters =
            Map.update(
              state.counters,
              metric_atom,
              1,
              &(&1 + 1)
            )

          %{state | counters: updated_counters}
        end)
      rescue
        error ->
          AppLogger.error("Failed to track metric", %{
            metric: metric_name,
            error: inspect(error)
          })
      end
    else
      AppLogger.error("Attempted to track unregistered metric", %{
        metric: metric_name,
        available_metrics: Map.keys(@registered_metrics)
      })
    end
  end

  @doc """
  Gets all the current metric values.
  """
  def get_metrics do
    try do
      Agent.get(@agent_name, fn state ->
        %{
          counters: state.counters,
          since: state.timestamp
        }
      end)
    rescue
      error ->
        AppLogger.error("Failed to get metrics", %{
          error: inspect(error)
        })

        %{
          counters: %{},
          since: DateTime.utc_now(),
          error: inspect(error)
        }
    end
  end

  @doc """
  Resets all metrics to zero.
  """
  def reset_metrics do
    try do
      Agent.update(@agent_name, fn _state ->
        %{
          counters: %{},
          timestamp: DateTime.utc_now()
        }
      end)
    rescue
      error ->
        AppLogger.error("Failed to reset metrics", %{
          error: inspect(error)
        })

        :error
    end
  end
end
