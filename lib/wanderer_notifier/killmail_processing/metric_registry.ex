defmodule WandererNotifier.KillmailProcessing.MetricRegistry do
  @moduledoc """
  Registers metrics-related atoms to prevent 'non-existing atom' errors.
  This module ensures that all metric keys used by the Metrics module
  are pre-registered as atoms during application startup.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  # List of processing modes
  @processing_modes ["realtime", "historical", "manual", "batch", "unknown"]

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

  @doc """
  Helper function to check for metrics synchronization issues between registry and Metrics module.
  Useful for debugging during development.
  """
  def check_registry_synchronization do
    # Alias the Metrics module
    alias WandererNotifier.KillmailProcessing.Metrics

    # Get registry metrics as strings
    registry_metrics = build_metric_keys() |> Enum.map(&Atom.to_string/1)

    # Get metrics module registered metrics using reflection (only in dev/test)
    metrics_map = get_registered_metrics_safely()

    # Metrics that are in registry but not in Metrics module
    missing_in_metrics = Enum.filter(registry_metrics, fn m -> !Map.has_key?(metrics_map, m) end)

    # Return diagnostic information
    %{
      registry_metrics_count: length(registry_metrics),
      metrics_module_count: map_size(metrics_map),
      missing_in_metrics_count: length(missing_in_metrics),
      missing_in_metrics_samples: Enum.take(missing_in_metrics, 10)
    }
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
