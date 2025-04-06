defmodule WandererNotifier.KillmailProcessing.MetricRegistry do
  @moduledoc """
  Registers metrics-related atoms to prevent 'non-existing atom' errors.
  This module ensures that all metric keys used by the Metrics module
  are pre-registered as atoms during application startup.

  IMPORTANT: The metric keys generated here must match those in
  WandererNotifier.KillmailProcessing.Metrics@registered_metrics exactly.
  If you add metrics to one module, you must update the other.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  # List of processing modes
  @processing_modes ["realtime", "historical", "manual", "batch"]

  # List of metric operations - MUST match the keys in Metrics@registered_metrics
  @metric_operations [
    # Base processing metrics
    "start",
    "complete",
    "complete.success",
    "complete.error",
    "skipped",
    "error",
    # Only the metric name without the mode part
    "persistence",
    # Notification metrics
    "notification.sent"
  ]

  @doc """
  Initializes all atom keys used for metrics.
  Call this function during application startup.
  """
  def initialize do
    AppLogger.startup_info("Initializing metric registry...")

    # Create all combinations of metric keys
    metric_atoms = build_metric_keys()

    # Count the number of registered atoms
    count = length(metric_atoms)

    AppLogger.startup_info("Registered metric atoms", %{
      count: count,
      category: "killmail_metrics"
    })

    # Return the list of registered atoms
    {:ok, metric_atoms}
  end

  @doc """
  Returns a list of all registered metric atom keys.
  """
  def registered_metrics do
    build_metric_keys()
  end

  # Private function to build all metric keys
  defp build_metric_keys do
    # Add base processing metrics (with killmail.processing prefix)
    processing_metrics =
      for operation <- @metric_operations,
          mode <- @processing_modes,
          !String.starts_with?(operation, "notification.") do
        if operation == "persistence" do
          # Special case for persistence metrics
          "killmail.#{operation}.#{mode}"
        else
          # Normal processing metrics
          "killmail.processing.#{mode}.#{operation}"
        end
      end

    # Add notification metrics (with killmail.notification prefix)
    notification_metrics =
      for mode <- @processing_modes do
        "killmail.notification.#{mode}.sent"
      end

    # Combine all metrics
    (processing_metrics ++ notification_metrics)
    |> Enum.uniq()
    |> Enum.map(&String.to_atom/1)
  end
end
