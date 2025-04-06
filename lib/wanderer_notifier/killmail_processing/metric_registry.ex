defmodule WandererNotifier.KillmailProcessing.MetricRegistry do
  @moduledoc """
  Registers metrics-related atoms to prevent 'non-existing atom' errors.
  This module ensures that all metric keys used by the Metrics module
  are pre-registered as atoms during application startup.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  # List of processing modes
  @processing_modes ["realtime", "historical", "manual", "batch"]

  # List of metric operations
  @metric_operations [
    "start",
    "skipped",
    "error",
    "persistence",
    "processing.realtime.complete",
    "processing.historical.complete",
    "processing.manual.complete",
    "processing.batch.complete",
    "processing.realtime.complete.success",
    "processing.historical.complete.success",
    "processing.manual.complete.success",
    "processing.batch.complete.success",
    "processing.realtime.complete.error",
    "processing.historical.complete.error",
    "processing.manual.complete.error",
    "processing.batch.complete.error",
    "notification.realtime.sent",
    "notification.historical.sent",
    "notification.manual.sent",
    "notification.batch.sent"
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
    # Generate the full set of metric keys
    # Create a key for the specific combination
    # Create the atom to ensure it exists
    # Also register these simplified metrics
    (for operation <- @metric_operations,
         mode <- @processing_modes do
       key = "killmail.processing.#{mode}.#{operation}"
       String.to_atom(key)
     end ++
       for mode <- @processing_modes do
         [
           String.to_atom("killmail.processing.#{mode}.start"),
           String.to_atom("killmail.processing.#{mode}.skipped"),
           String.to_atom("killmail.processing.#{mode}.error"),
           String.to_atom("killmail.notification.#{mode}.sent")
         ]
       end)
    |> List.flatten()
    |> Enum.uniq()
  end
end
