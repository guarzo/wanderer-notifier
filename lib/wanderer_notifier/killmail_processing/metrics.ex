defmodule WandererNotifier.KillmailProcessing.Metrics do
  @moduledoc """
  Metrics collection and reporting for killmail processing.
  """

  require Logger

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.KillmailProcessing.Context
  alias WandererNotifier.KillmailProcessing.MetricRegistry

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

  defp increment_counter_impl(key) do
    # Check if the metric is registered in our metrics registry
    registered_metrics = MetricRegistry.registered_metrics()
    atom_key = String.to_atom(key)

    if atom_key in registered_metrics do
      # If the atom is registered, increment it
      Stats.increment(atom_key)
      :ok
    else
      # Log that we tried to use a non-registered atom
      require Logger
      Logger.warning("Attempted to track metrics with non-registered atom key: #{key}")
      :error
    end
  rescue
    error ->
      # Log any other errors
      require Logger
      Logger.warning("Error tracking metric [#{key}]: #{inspect(error)}")
      :error
  end
end
