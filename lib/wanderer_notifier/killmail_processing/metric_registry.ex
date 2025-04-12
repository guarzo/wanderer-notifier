defmodule WandererNotifier.KillmailProcessing.MetricRegistry do
  @moduledoc """
  Registers metrics-related atoms to prevent 'non-existing atom' errors.

  @deprecated Please use WandererNotifier.Killmail.Metrics.MetricRegistry instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Metrics.MetricRegistry.
  """

  require Logger
  alias WandererNotifier.Killmail.Metrics.MetricRegistry, as: NewMetricRegistry

  # List of processing modes
  @processing_modes ["realtime", "historical", "manual", "batch", "unknown"]

  @doc """
  Initializes all atom keys used for metrics.
  Call this function during application startup.

  @deprecated Please use WandererNotifier.Killmail.Metrics.MetricRegistry.initialize/0 instead
  """
  def initialize do
    Logger.warning("Using deprecated MetricRegistry.initialize/0, please update your code")
    NewMetricRegistry.initialize()
  end

  @doc """
  Returns a list of all registered metric atom keys.

  @deprecated Please use WandererNotifier.Killmail.Metrics.MetricRegistry.registered_metrics/0 instead
  """
  def registered_metrics do
    Logger.warning("Using deprecated MetricRegistry.registered_metrics/0, please update your code")
    NewMetricRegistry.registered_metrics()
  end

  @doc """
  Helper function to check for metrics synchronization issues between registry and Metrics module.
  Useful for debugging during development.

  @deprecated Please use WandererNotifier.Killmail.Metrics.MetricRegistry.check_registry_synchronization/0 instead
  """
  def check_registry_synchronization do
    Logger.warning("Using deprecated MetricRegistry.check_registry_synchronization/0, please update your code")
    NewMetricRegistry.check_registry_synchronization()
  end

  # Safely gets registered metrics from the Metrics module
  defp get_registered_metrics_safely do
    alias WandererNotifier.KillmailProcessing.Metrics

    # Check if module exists and has the required function
    if Code.ensure_loaded?(Metrics) &&
         function_exported?(Metrics, :__registered_metrics_for_debug__, 0) do
      Metrics.__registered_metrics_for_debug__()
    else
      %{}
    end
  end

  # Private function to build all metric keys
  defp build_metric_keys do
    # Generate the base set of metric keys that match the format expected in the Metrics module
    base_metrics =
      for mode <- @processing_modes do
        [
          # Base processing metrics
          String.to_atom("killmail.processing.#{mode}.start"),
          String.to_atom("killmail.processing.#{mode}.complete"),
          String.to_atom("killmail.processing.#{mode}.complete.success"),
          String.to_atom("killmail.processing.#{mode}.complete.error"),
          String.to_atom("killmail.processing.#{mode}.skipped"),
          String.to_atom("killmail.processing.#{mode}.error"),

          # Persistence metrics
          String.to_atom("killmail.persistence.#{mode}"),

          # Notification metrics
          String.to_atom("killmail.notification.#{mode}.sent"),

          # Combined metrics directly added rather than generated
          String.to_atom("killmail.processing.#{mode}.persistence"),

          # Also add the problematic metrics we've seen in logs
          String.to_atom("killmail.processing.#{mode}.complete.#{mode}")
        ]
      end
      |> List.flatten()
      |> Enum.uniq()

    # Log the metrics we're registering
    IO.puts("Registering #{length(base_metrics)} metrics")
    base_metrics
  end
end
