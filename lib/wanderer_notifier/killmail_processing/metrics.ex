defmodule WandererNotifier.KillmailProcessing.Metrics do
  @moduledoc """
  Metrics collection and reporting for killmail processing.
  """

  require Logger

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.KillmailProcessing.Context

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
    metric_key = "killmail.processing.#{mode_name(ctx)}.complete"
    increment_counter(metric_key)

    case result do
      {:ok, _} ->
        increment_counter("#{metric_key}.success")

      {:error, _} ->
        increment_counter("#{metric_key}.error")
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
  def track_persistence(%Context{} = ctx) do
    metric_key = "killmail.persistence.#{mode_name(ctx)}"
    increment_counter(metric_key)
    :ok
  end

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

  defp mode_name(%Context{mode: %{mode: mode}}), do: Atom.to_string(mode)

  defp increment_counter(key) do
    # Track metrics using Core Stats
    Stats.increment(String.to_atom(key))
    :ok
  end
end
